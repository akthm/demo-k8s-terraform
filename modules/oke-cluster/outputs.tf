################################################################################
# OKE Cluster Module - Outputs
################################################################################

output "cluster_id" {
  description = "The OCID of the OKE cluster"
  value       = oci_containerengine_cluster.main.id
}

output "cluster_name" {
  description = "The name of the OKE cluster"
  value       = oci_containerengine_cluster.main.name
}

output "cluster_kubernetes_version" {
  description = "The Kubernetes version of the cluster"
  value       = oci_containerengine_cluster.main.kubernetes_version
}

output "cluster_state" {
  description = "The current state of the cluster"
  value       = oci_containerengine_cluster.main.state
}

output "cluster_endpoint" {
  description = "The Kubernetes API endpoint"
  value       = oci_containerengine_cluster.main.endpoints[0].kubernetes
}

output "cluster_private_endpoint" {
  description = "The private Kubernetes API endpoint"
  value       = oci_containerengine_cluster.main.endpoints[0].private_endpoint
}

output "cluster_public_endpoint" {
  description = "The public Kubernetes API endpoint"
  value       = oci_containerengine_cluster.main.endpoints[0].public_endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate for Kubernetes provider"
  value       = base64decode(yamldecode(data.oci_containerengine_cluster_kube_config.main.content).clusters[0].cluster["certificate-authority-data"])
  sensitive   = true
}

output "kubeconfig" {
  description = "The kubeconfig content for the cluster"
  value       = data.oci_containerengine_cluster_kube_config.main.content
  sensitive   = true
}

output "vcn_id" {
  description = "The OCID of the VCN (pass-through)"
  value       = var.vcn_id
}
