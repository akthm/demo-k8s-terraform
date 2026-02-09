terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

provider "kubectl" {
  config_path = var.kubeconfig_path
}

# Install MetalLB via Helm
resource "helm_release" "metallb" {
  name             = "metallb"
  repository       = "https://metallb.github.io/metallb"
  chart            = "metallb"
  version          = var.metallb_version
  namespace        = "metallb-system"
  create_namespace = true

  wait    = true
  timeout = 300
}

# Wait for MetalLB controller to be ready before creating CRDs
resource "null_resource" "wait_for_metallb" {
    depends_on = [helm_release.metallb]

    provisioner "local-exec" {
        on_failure = continue
        when = create
        command = "kubectl --kubeconfig=${var.kubeconfig_path} wait --namespace=metallb-system --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s"
    }
}

# Configure IP Address Pool
resource "kubectl_manifest" "ip_address_pool" {
  depends_on = [null_resource.wait_for_metallb]

  yaml_body = <<-YAML
    apiVersion: metallb.io/v1beta1
    kind: IPAddressPool
    metadata:
      name: ${var.ip_address_pool.name}
      namespace: metallb-system
    spec:
      addresses:
        %{for addr in var.ip_address_pool.addresses~}
        - ${addr}
        %{endfor~}
  YAML
}

# Configure L2 Advertisement for Layer 2 mode
resource "kubectl_manifest" "l2_advertisement" {
  depends_on = [kubectl_manifest.ip_address_pool]

  yaml_body = <<-YAML
    apiVersion: metallb.io/v1beta1
    kind: L2Advertisement
    metadata:
      name: default
      namespace: metallb-system
    spec:
      ipAddressPools:
        - ${var.ip_address_pool.name}
  YAML
}
