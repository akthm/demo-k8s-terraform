
#### Helm chart to deploy LocalStack in Kind cluster
## only deployed if platform is "kind"


resource "helm_release" "local_stack" {
  count = var.platform == "kind" ? 1 : 0
 
  name       = "local-stack"
  repository = "https://localstack.github.io/helm-charts"
  chart      = "localstack"
  namespace  = "localstack"
  create_namespace = true
  version    = "0.6.27"
  
  # Increase timeout for Kind
  timeout = 300  # 5 minutes
  wait    = true
  values = [yamlencode({
    extraEnvVars = [
      { name = "SERVICES", value = "secretsmanager,kms" },
      { name = "DEBUG",    value = "1" },
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

resource "helm_release" "ESO" {
  count = var.platform == "kind" ? 1 : 0
  
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  namespace  = "external-secrets"
  create_namespace = true
  version    = "1.1.1"
  values = [
    yamlencode({
      installCRDs = true
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