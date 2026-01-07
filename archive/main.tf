/**
 * ==============================================================================
 * Root Orchestration Module - AWS EKS with Cluster Services
 * ==============================================================================
 * 
 * This is the PRIMARY entry point for your infrastructure.
 * It orchestrates the deployment of:
 *   1. VPC & Networking Infrastructure
 *   2. AWS EKS Cluster
 *   3. EKS Addons (CoreDNS, VPC-CNI, Kube-Proxy, EBS CSI)
 *   4. Cluster Services (ArgoCD, External Secrets, Load Balancer Controller)
 * 
 * All data flows through this file. No resource definitions belong here—only
 * module calls and data sources that bridge modules together.
 * ==============================================================================
 */

# ===============================================================================
# Data: Get EKS Cluster Auth Token (depends on EKS cluster existing)
# ===============================================================================

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

# ===============================================================================
# 1. EKS Cluster & Infrastructure
# ===============================================================================

module "eks" {
  source = "./modules/eks"

  # Pass through all variables
  common_tags     = var.common_tags
  region          = var.region
  vpc_cidrs       = var.vpc_cidrs
  ha              = var.ha
  cluster_version = var.cluster_version
  node_type       = var.node_type
}

# ===============================================================================
# Kubernetes Provider Configuration (Post-EKS)
# ===============================================================================

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# ===============================================================================
# Helm Provider Configuration (Post-EKS)
# ===============================================================================

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# ===============================================================================
# 2. Cluster Services (ArgoCD, External Secrets, Load Balancer Controller)
# ===============================================================================

module "cluster_services" {
  source = "./modules/cluster_services"

  # Cluster identification
  cluster_name                       = module.eks.cluster_name
  cluster_endpoint                   = module.eks.cluster_endpoint
  cluster_certificate_authority_data = module.eks.cluster_certificate_authority_data
  cluster_oidc_issuer_url            = module.eks.cluster_oidc_issuer_url
  cluster_oidc_provider_arn          = module.eks.oidc_provider_arn

  # AWS region
  aws_region = var.region

  # ArgoCD configuration
  argocd_app_of_apps_repo_url  = var.argocd_app_of_apps_repo_url
  argocd_app_of_apps_repo_path = var.argocd_app_of_apps_repo_path

  depends_on = [module.eks]
}

# ===============================================================================
# 3. Root Outputs
# ===============================================================================

output "eks_cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "The endpoint for the EKS cluster API"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_security_groups" {
  description = "Security group information for the EKS cluster"
  value       = module.eks.cluster_security_groups
}

output "kubeconfig_command" {
  description = "Command to configure kubectl for this cluster"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "cluster_services_status" {
  description = "Status of deployed cluster services"
  value = {
    argocd_namespace              = "argocd"
    external_secrets_namespace    = "external-secrets"
    load_balancer_namespace       = "kube-system"
  }
}
