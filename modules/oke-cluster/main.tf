################################################################################
# OKE Cluster Module - OCI Kubernetes Engine Control Plane
# BASIC_CLUSTER type to stay within Always Free tier (no control plane fee)
################################################################################

# OKE Cluster
resource "oci_containerengine_cluster" "main" {
  compartment_id     = var.compartment_id
  kubernetes_version = var.kubernetes_version
  name               = var.cluster_name
  vcn_id             = var.vcn_id

  # CRITICAL: Use BASIC_CLUSTER to avoid control plane charges
  type = var.cluster_type

  cluster_pod_network_options {
    cni_type = var.cni_type
  }

  endpoint_config {
    is_public_ip_enabled = var.endpoint_public
    subnet_id            = var.endpoint_subnet_id
  }

  options {
    add_ons {
      is_kubernetes_dashboard_enabled = var.enable_dashboard
      is_tiller_enabled               = false # Deprecated, always false
    }

    kubernetes_network_config {
      pods_cidr     = var.pods_cidr
      services_cidr = var.services_cidr
    }

    service_lb_subnet_ids = var.service_lb_subnet_ids
  }

  freeform_tags = var.common_tags
}

# Get kubeconfig for the cluster
data "oci_containerengine_cluster_kube_config" "main" {
  cluster_id = oci_containerengine_cluster.main.id

  # Token-based auth (recommended)
  token_version = "2.0.0"
}
