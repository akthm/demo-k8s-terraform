/**
 * ==============================================================================
 * EKS Module Outputs
 * ==============================================================================
 * 
 * These outputs are consumed by:
 *   - Root module (for final outputs)
 *   - Cluster services module (for Kubernetes/Helm provider configuration)
 *   - Other dependent resources
 * ==============================================================================
 */

output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "The endpoint for EKS cluster API"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate authority data for the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Provider for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "cluster_security_groups" {
  description = "Security groups associated with the EKS cluster"
  value = {
    "cluster_primary_security_group_id" = module.eks.cluster_primary_security_group_id
    "cluster_security_group_id"         = module.eks.cluster_security_group_id
    "node_security_group_id"            = module.eks.node_security_group_id
  }
}

output "kubeconfig_update_command" {
  description = "Command to update your local kubeconfig"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}