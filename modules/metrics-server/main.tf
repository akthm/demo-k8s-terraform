# Metrics Server Module
# Platform-aware metrics-server installation for Kubernetes clusters

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0.0"
    }
  }
}

locals {
  # Kind requires insecure TLS patches
  is_kind = var.platform == "kind"
  
  # Context name
  kube_context = var.kube_context != "" ? var.kube_context : (
    local.is_kind ? "kind-${var.cluster_name}" : var.cluster_name
  )
}

# Install via Helm (preferred for OKE/EKS)
resource "helm_release" "metrics_server" {
  count = var.use_helm ? 1 : 0

  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = var.namespace
  version    = var.helm_version

  create_namespace = false # kube-system already exists

  values = [
    yamlencode({
      args = local.is_kind ? [
        "--kubelet-insecure-tls",
        "--kubelet-preferred-address-types=InternalIP,Hostname,InternalDNS,ExternalDNS,ExternalIP"
      ] : []
      
      resources = {
        requests = {
          cpu    = "100m"
          memory = "200Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "400Mi"
        }
      }
    })
  ]

  wait    = true
  timeout = 300
}

# Install via manifest (for Kind or when Helm not preferred)
resource "null_resource" "metrics_server_manifest" {
  count = var.use_helm ? 0 : 1

  triggers = {
    cluster_name = var.cluster_name
    kube_context = local.kube_context
    platform     = var.platform
    cluster_id   = var.cluster_trigger_id
  }

  provisioner "local-exec" {
    when        = create
    on_failure  = fail
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
      set -euo pipefail

      echo "Installing metrics-server..."
      kubectl --context ${self.triggers.kube_context} apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

      ${local.is_kind ? <<-PATCH
      echo "Patching metrics-server for Kind (kubelet insecure TLS)..."
      kubectl --context ${self.triggers.kube_context} -n kube-system patch deployment metrics-server --type='json' -p='[
        {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"},
        {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-preferred-address-types=InternalIP,Hostname,InternalDNS,ExternalDNS,ExternalIP"}
      ]'
      PATCH
      : "# No patches needed for ${var.platform}"}

      echo "Waiting for metrics-server rollout..."
      kubectl --context ${self.triggers.kube_context} -n kube-system rollout status deployment/metrics-server --timeout=180s

      echo "Verifying Metrics API availability..."
      for i in $(seq 1 30); do
        if kubectl --context ${self.triggers.kube_context} get --raw /apis/metrics.k8s.io/v1beta1 >/dev/null 2>&1; then
          echo "✅ metrics.k8s.io API is available"
          exit 0
        fi
        echo "Retry $i/30: waiting for metrics API..."
        sleep 3
      done

      echo "❌ metrics.k8s.io API not available in time"
      kubectl --context ${self.triggers.kube_context} -n kube-system logs deployment/metrics-server --tail=200 || true
      exit 1
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    on_failure  = continue
    command     = <<-EOT
      set -euo pipefail
      echo "Removing metrics-server..."
      kubectl --context ${self.triggers.kube_context} delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml --ignore-not-found
    EOT
  }
}
