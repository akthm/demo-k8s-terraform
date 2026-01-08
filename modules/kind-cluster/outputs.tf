output "cluster_name" {
  description = "The name of the KIND cluster"
  value       = var.cluster_name
}

output "kube_context" {
  description = "The kubectl context name for the KIND cluster"
  value       = "kind-${var.cluster_name}"
}

output "cluster_endpoint" {
  description = "The API endpoint for the cluster (for compatibility)"
  value       = "https://127.0.0.1:6443"
}

output "cluster_certificate_authority_data" {
  description = "The CA data for the cluster (placeholder for local KIND)"
  value       = "local-kind-ca"
}
