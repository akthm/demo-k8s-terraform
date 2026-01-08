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
    command = <<-EOT
      if kind get clusters 2>/dev/null | grep -q "^${self.triggers.cluster_name}$"; then
        kind delete cluster --name ${self.triggers.cluster_name}
      else
        echo "Cluster ${self.triggers.cluster_name} does not exist, skipping deletion"
      fi
    EOT
  }
}
