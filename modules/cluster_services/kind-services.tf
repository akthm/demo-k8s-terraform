
#### Helm chart to deploy LocalStack in Kind cluster
## only deployed if platform is "kind"


resource "helm_release" "local_stack" {
  count = var.platform == "kind" ? 1 : 0

  name             = "local-stack"
  repository       = "https://localstack.github.io/helm-charts"
  chart            = "localstack"
  namespace        = "localstack"
  create_namespace = true
  version          = "0.6.27"

  # Increase timeout for Kind
  timeout = 300 # 5 minutes
  wait    = true
  values = [yamlencode({
    extraEnvVars = [
      { name = "SERVICES", value = "secretsmanager,kms" },
      { name = "DEBUG", value = "1" },
      { name = "DATA_DIR", value = "/tmp/localstack/data" },
    ]
    persistence = { enabled = false }
    service = {
      type       = "ClusterIP"
      port       = 4566
      targetPort = 4566
    }
  })]

}

# Cleanup LocalStack namespace before destruction
resource "null_resource" "localstack_namespace_cleanup" {
  count = var.platform == "kind" ? 1 : 0

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set +e
      echo "=== Force cleaning LocalStack namespace ==="
      
      # Delete all resources in namespace with force
      kubectl delete all --all -n localstack --grace-period=0 --force --timeout=30s 2>/dev/null || true
      
      # Remove finalizers from all resources
      for resource in $(kubectl api-resources --verbs=list --namespaced -o name); do
        kubectl get $resource -n localstack -o name 2>/dev/null | xargs -r -I {} kubectl patch {} -n localstack -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
      done
      
      # Force delete the namespace
      kubectl delete namespace localstack --grace-period=0 --force --timeout=10s 2>/dev/null || true
      
      # Remove namespace finalizers if still stuck
      kubectl patch namespace localstack -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
      
      echo "=== LocalStack namespace cleanup completed ==="
    EOT
  }

  depends_on = [
    helm_release.local_stack[0]
  ]
}

resource "helm_release" "ESO" {
  count = var.platform == "kind" ? 1 : 0

  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  version          = "1.1.1"
  values = [
    yamlencode({
      installCRDs  = true
      replicaCount = 1
      serviceAccount = {
        create = true
        name   = "external-secrets-sa"
      }
      annotations = {
        "eks.amazonaws.com/role-arn" = "arn:aws:iam::000000000000:role/external-secrets-role"
      }
    })
  ]

  depends_on = [helm_release.local_stack[0]]

}

# Cleanup External Secrets namespace before destruction
resource "null_resource" "eso_namespace_cleanup" {
  count = var.platform == "kind" ? 1 : 0

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set +e
      echo "=== Force cleaning External Secrets namespace ==="
      
      # Remove finalizers from all ClusterSecretStores
      for css in $(kubectl get clustersecretstores -o name 2>/dev/null || true); do
        kubectl patch $css -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
      done
      kubectl delete clustersecretstores --all --grace-period=0 --force --timeout=10s 2>/dev/null || true
      
      # Remove finalizers from all SecretStores
      for ss in $(kubectl get secretstores -n external-secrets -o name 2>/dev/null || true); do
        kubectl patch $ss -n external-secrets -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
      done
      kubectl delete secretstores --all -n external-secrets --grace-period=0 --force --timeout=10s 2>/dev/null || true
      
      # Remove finalizers from all ExternalSecrets
      for es in $(kubectl get externalsecrets -n external-secrets -o name 2>/dev/null || true); do
        kubectl patch $es -n external-secrets -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
      done
      kubectl delete externalsecrets --all -n external-secrets --grace-period=0 --force --timeout=10s 2>/dev/null || true
      
      # Delete all resources in namespace with force
      kubectl delete all --all -n external-secrets --grace-period=0 --force --timeout=30s 2>/dev/null || true
      
      # Remove finalizers from all remaining resources
      for resource in $(kubectl api-resources --verbs=list --namespaced -o name); do
        kubectl get $resource -n external-secrets -o name 2>/dev/null | xargs -r -I {} kubectl patch {} -n external-secrets -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
      done
      
      # Force delete the namespace
      kubectl delete namespace external-secrets --grace-period=0 --force --timeout=10s 2>/dev/null || true
      
      # Remove namespace finalizers if still stuck
      kubectl patch namespace external-secrets -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
      
      echo "=== External Secrets namespace cleanup completed ==="
    EOT
  }

  depends_on = [
    helm_release.ESO[0],
    null_resource.configure_eso_for_localstack[0]
  ]
}

resource "null_resource" "wait_for_eso" {
  count = var.platform == "kind" ? 1 : 0

  depends_on = [helm_release.ESO[0]]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for External Secrets Operator to be ready..."
      kubectl wait --for=condition=Available --timeout=120s deployment/external-secrets -n external-secrets --context kind-${var.cluster_name}
      echo "External Secrets Operator is ready!"
    EOT
  }
}

# Configure ESO for LocalStack to simulate IRSA
resource "null_resource" "configure_eso_for_localstack" {
  count = var.platform == "kind" ? 1 : 0

  depends_on = [null_resource.wait_for_eso[0]]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Configuring External Secrets Operator for LocalStack..."
      
      # Add IAM role annotation to service account
      kubectl annotate serviceaccount external-secrets-sa -n external-secrets \
        eks.amazonaws.com/role-arn=arn:aws:iam::000000000000:role/external-secrets-role \
        --overwrite \
        --context kind-${var.cluster_name}
      
      # Inject AWS credentials and endpoint URLs as environment variables
      kubectl set env deployment/external-secrets -n external-secrets \
        AWS_ACCESS_KEY_ID=test \
        AWS_SECRET_ACCESS_KEY=test \
        AWS_ENDPOINT_URL=http://local-stack-localstack.localstack.svc.cluster.local:4566 \
        --context kind-${var.cluster_name}
      
      echo "Waiting for ESO to restart with new configuration..."
      kubectl rollout status deployment/external-secrets -n external-secrets --context kind-${var.cluster_name} --timeout=120s
      echo "External Secrets Operator configured for LocalStack!"
    EOT
  }
}

# ===============================================================================
# ClusterSecretStore for LocalStack
# ===============================================================================
# This creates a ClusterSecretStore CRD that points to LocalStack's Secrets Manager
# enabling cross-namespace secret synchronization

resource "kubernetes_secret" "localstack_credentials" {
  count = var.platform == "kind" ? 1 : 0

  metadata {
    name      = "localstack-credentials"
    namespace = "external-secrets"
  }

  data = {
    "access-key" = "test" # LocalStack default
    "secret-key" = "test" # LocalStack default
  }

  depends_on = [helm_release.ESO[0]]
}

resource "null_resource" "create_cluster_secret_store" {
  count = var.platform == "kind" ? 1 : 0

  depends_on = [
    null_resource.configure_eso_for_localstack[0],
    kubernetes_secret.localstack_credentials[0]
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Creating ClusterSecretStore for LocalStack..."
      
      cat <<EOF | kubectl apply --context kind-${var.cluster_name} -f -
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        secretRef:
          accessKeyIDSecretRef:
            name: localstack-credentials
            namespace: external-secrets
            key: access-key
          secretAccessKeySecretRef:
            name: localstack-credentials
            namespace: external-secrets
            key: secret-key
      additionalRoles: []
      sessionTags: []
EOF

      # Patch the ClusterSecretStore to use LocalStack endpoint
      # Note: ESO uses AWS_ENDPOINT_URL env var set earlier for endpoint override
      
      echo "ClusterSecretStore created for LocalStack!"
    EOT
  }
}

# Verify ClusterSecretStore is ready
resource "null_resource" "verify_cluster_secret_store" {
  count = var.platform == "kind" ? 1 : 0

  depends_on = [null_resource.create_cluster_secret_store[0]]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Verifying ClusterSecretStore status..."
      
      # Wait for the ClusterSecretStore to be ready
      for i in $(seq 1 30); do
        STATUS=$(kubectl get clustersecretstore aws-secrets-manager --context kind-${var.cluster_name} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "NotFound")
        if [ "$STATUS" = "True" ]; then
          echo "ClusterSecretStore is ready!"
          exit 0
        fi
        echo "Waiting for ClusterSecretStore to be ready... ($i/30)"
        sleep 2
      done
      
      echo "Warning: ClusterSecretStore may not be ready yet. Check status with:"
      echo "kubectl get clustersecretstore aws-secrets-manager -o yaml"
    EOT
  }
}
