################################################################################
# OKE-Specific Services
# Resources deployed only when platform is "oke"
################################################################################

# cert-manager for Let's Encrypt TLS certificates
resource "helm_release" "cert_manager" {
  count = var.platform == "oke" && var.install_cert_manager ? 1 : 0

  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"
  version    = "v1.14.0"

  create_namespace = true
  timeout          = 300
  wait             = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  values = [
    yamlencode({
      resources = {
        limits   = { cpu = "100m", memory = "256Mi" }
        requests = { cpu = "50m", memory = "128Mi" }
      }
    })
  ]
}

resource "null_resource" "wait_for_cert_manager_crds" {
  count = var.platform == "oke" && var.install_cert_manager ? 1 : 0

  depends_on = [helm_release.cert_manager]

  provisioner "local-exec" {
    when    = create
    command = <<-EOT
      set -e
      echo "Waiting for cert-manager CRDs..."
      kubectl wait --for=condition=Established crd/certificates.cert-manager.io --timeout=120s
      kubectl wait --for=condition=Established crd/certificaterequests.cert-manager.io --timeout=120s
      kubectl wait --for=condition=Established crd/issuers.cert-manager.io --timeout=120s
      kubectl wait --for=condition=Established crd/clusterissuers.cert-manager.io --timeout=120s
      echo "cert-manager CRDs are ready"
    EOT
  }
}

# ClusterIssuer for Let's Encrypt using kubectl (avoids plan-time CRD validation)
resource "null_resource" "letsencrypt_staging" {
  count = var.platform == "oke" && var.install_cert_manager ? 1 : 0

  depends_on = [null_resource.wait_for_cert_manager_crds]

  triggers = {
    email = var.cert_manager_email
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl apply -f - <<EOF
      apiVersion: cert-manager.io/v1
      kind: ClusterIssuer
      metadata:
        name: letsencrypt-staging
      spec:
        acme:
          server: https://acme-staging-v02.api.letsencrypt.org/directory
          email: ${var.cert_manager_email}
          privateKeySecretRef:
            name: letsencrypt-staging-key
          solvers:
          - http01:
              ingress:
                class: nginx
      EOF
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kubectl delete clusterissuer letsencrypt-staging --ignore-not-found=true"
  }
}

resource "null_resource" "letsencrypt_prod" {
  count = var.platform == "oke" && var.install_cert_manager ? 1 : 0

  depends_on = [null_resource.wait_for_cert_manager_crds]

  triggers = {
    email = var.cert_manager_email
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl apply -f - <<EOF
      apiVersion: cert-manager.io/v1
      kind: ClusterIssuer
      metadata:
        name: letsencrypt-prod
      spec:
        acme:
          server: https://acme-v02.api.letsencrypt.org/directory
          email: ${var.cert_manager_email}
          privateKeySecretRef:
            name: letsencrypt-prod-key
          solvers:
          - http01:
              ingress:
                class: nginx
      EOF
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kubectl delete clusterissuer letsencrypt-prod --ignore-not-found=true"
  }
}

################################################################################
# External Secrets Operator for OCI Vault Integration
################################################################################

resource "helm_release" "external_secrets_oke" {
  count = var.platform == "oke" && var.install_external_secrets ? 1 : 0

  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  namespace  = "external-secrets"
  version    = "0.9.11"

  create_namespace = true
  timeout          = 300
  wait             = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  values = [
    yamlencode({
      resources = {
        limits   = { cpu = "100m", memory = "256Mi" }
        requests = { cpu = "50m", memory = "128Mi" }
      }
    })
  ]
}

# Wait for External Secrets CRDs to be ready
resource "null_resource" "wait_for_eso_crds" {
  count = var.platform == "oke" && var.install_external_secrets ? 1 : 0

  depends_on = [helm_release.external_secrets_oke]

  provisioner "local-exec" {
    when    = create
    command = <<-EOT
      set -e
      echo "Waiting for External Secrets CRDs..."
      kubectl wait --for=condition=Established crd/clustersecretstores.external-secrets.io --timeout=120s
      kubectl wait --for=condition=Established crd/externalsecrets.external-secrets.io --timeout=120s
      echo "External Secrets CRDs are ready"
    EOT
  }
}

# ClusterSecretStore for OCI Vault (instance principal auth)
# Using null_resource with kubectl to avoid plan-time CRD validation issues
# NOTE: Auth section is OMITTED to use Instance Principal authentication
resource "null_resource" "oci_vault_cluster_secret_store" {
  count = var.platform == "oke" && var.install_external_secrets && var.oci_vault_id != "" ? 1 : 0

  depends_on = [null_resource.wait_for_eso_crds]

  triggers = {
    vault_id = var.oci_vault_id
    region   = var.oci_region
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl apply -f - <<EOF
      apiVersion: external-secrets.io/v1beta1
      kind: ClusterSecretStore
      metadata:
        name: oci-vault
      spec:
        provider:
          oracle:
            vault: ${var.oci_vault_id}
            region: ${var.oci_region}
      EOF
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kubectl delete clustersecretstore oci-vault --ignore-not-found=true"
  }
}
