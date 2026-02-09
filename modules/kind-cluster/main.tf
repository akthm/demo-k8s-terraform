variable "cluster_name" {
  type = string
}

variable "kind_config_path" {
  type = string
}
resource "null_resource" "kind_cluster" {
  triggers = {
    cluster_name = var.cluster_name
    config_sha   = filesha256(var.kind_config_path)
  }

  provisioner "local-exec" {
    command = "kind version || (echo 'Kind is not installed. Please install Kind to proceed.' && exit 1)"
    on_failure = fail
  }

  provisioner "local-exec" {
    when = create
    command = <<-EOT
      set -e
      if kind get clusters | grep -q "^${var.cluster_name}$"; then
        echo "Cluster ${var.cluster_name} already exists, deleting it first..."
        kind delete cluster --name ${var.cluster_name}
      fi
      kind create cluster --name ${var.cluster_name} --config ${var.kind_config_path}
    EOT
    on_failure = fail
  }
  
  provisioner "local-exec" {
    when = create
    command = <<-EOT
      set -e
      echo "Waiting for kind cluster to be ready..."

      for i in $(seq 1 30); do
        if kubectl wait --for=condition=Ready nodes --all --timeout=120s --context kind-local-dev 2>/dev/null; then
          break
        fi
        echo "Retry $i/30: Waiting for nodes..."
        sleep 5
      done

      for i in $(seq 1 30); do
        if kubectl wait --for=condition=Ready pods -n kube-system -l k8s-app=kube-dns --timeout=30s --context kind-local-dev 2>/dev/null; then
          echo "Kind cluster is ready!"
          exit 0
        fi
        echo "Retry $i/30: Waiting for DNS..."
        sleep 5
      done

      echo "Cluster failed to become ready in time"
exit 1
    EOT
    on_failure = fail
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
      if kind get clusters 2>/dev/null | grep -q "^${self.triggers.cluster_name}$"; then
        kind delete cluster --name ${self.triggers.cluster_name}
      else
        echo "Cluster ${self.triggers.cluster_name} does not exist, skipping deletion"
      fi
    EOT
  }
}


# --- Metrics Server install for Kind ---
resource "null_resource" "metrics_server" {
  depends_on = [null_resource.kind_cluster]

  triggers = {
    cluster_name = var.cluster_name
    kind_context = "kind-${var.cluster_name}"
    cluster_recreate = null_resource.kind_cluster.id

    # if you want to force re-run on every apply, add: run_id = timestamp()
  }



  provisioner "local-exec" {
    when       = create
    on_failure = fail
    interpreter = ["/bin/bash", "-c"]
    command = <<EOT
      set -euo pipefail

      echo "Installing metrics-server..."
      kubectl --context ${self.triggers.kind_context} apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

      echo "Patching metrics-server for kind (kubelet insecure TLS)..."
      kubectl --context ${self.triggers.kind_context} -n kube-system patch deployment metrics-server --type='json' -p='[
        {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"},
        {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-preferred-address-types=InternalIP,Hostname,InternalDNS,ExternalDNS,ExternalIP"}
      ]'

      echo "Waiting for metrics-server rollout..."
      kubectl --context ${self.triggers.kind_context} -n kube-system rollout status deployment/metrics-server --timeout=180s

      echo "Verifying Metrics API becomes available..."
      for i in $(seq 1 30); do
        if kubectl --context ${self.triggers.kind_context} get --raw /apis/metrics.k8s.io/v1beta1 >/dev/null 2>&1; then
          echo "✅ metrics.k8s.io API is available"
          exit 0
        fi
        echo "Retry $i/30: waiting for metrics API..."
        sleep 3
      done

      echo "❌ metrics.k8s.io API not available in time"
      kubectl --context ${self.triggers.kind_context} -n kube-system logs deployment/metrics-server --tail=200 || true
      exit 1
    EOT
  }

  provisioner "local-exec" {
    when = destroy
    interpreter = ["/bin/bash", "-c"]
    on_failure = continue
    command = <<-EOT
      set -euo pipefail
      echo "Removing metrics-server..."
          kubectl --context ${self.triggers.kind_context} delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml --ignore-not-found
    EOT
  }
}


