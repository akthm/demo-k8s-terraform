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

resource "time_sleep" "wait_for_cluster" {
  create_duration = "30s"

  depends_on = [module.eks]
}

# ===============================================================================
# 2. Cluster Services (ArgoCD + NGINX Ingress)
# ===============================================================================

module "cluster_services" {
  source = "./modules/cluster_services"

  # Cluster identification
  cluster_name                       = module.eks.cluster_name
  cluster_endpoint                   = module.eks.cluster_endpoint
  cluster_certificate_authority_data = module.eks.cluster_certificate_authority_data
  # cluster_oidc_provider_arn          = module.eks.cluster_oidc_provider_arn
  # cluster_oidc_issuer_url            = module.eks.cluster_oidc_issuer_url

  # AWS configuration
  # aws_region = var.region

  # ArgoCD configuration
  # argocd_hostname            = var.argocd_hostname
  argocd_repo_url  = var.argocd_repo_url
  argocd_repo_path = var.argocd_repo_path
  # argocd_app_of_apps_repo_url = var.argocd_app_of_apps_repo_url
  git_token              = var.git_token
  argocd_target_revision = var.argocd_target_revision
  argocd_version         = var.argocd_version

  depends_on = [
    module.eks,
    time_sleep.wait_for_cluster
  ]
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
    argocd_namespace           = "argocd"
    external_secrets_namespace = "external-secrets"
    cert_manager_namespace     = "cert-manager"
    nginx_ingress_namespace    = "ingress-nginx"
  }
}

# ===============================================================================
# ArgoCD Access Information
# ===============================================================================

output "argocd_access_mode" {
  description = "How to access ArgoCD"
  value       = "HTTP via LoadBalancer (/argo path)"
}

output "argocd_ui_url" {
  description = "URL to access ArgoCD UI (replace <LoadBalancer-IP> with actual IP)"
  value       = module.cluster_services.argocd_url
}

output "nginx_loadbalancer_info" {
  description = "Command to get NGINX LoadBalancer external IP for /argo access"
  value       = module.cluster_services.nginx_loadbalancer_command
}

output "argocd_port_forward_command" {
  description = "Command to port-forward ArgoCD UI for local access (without DNS/LoadBalancer)"
  value       = "kubectl -n argocd port-forward svc/argocd-server 8080:443"
}

output "argocd_port_forward_url" {
  description = "URL when using port-forward"
  value       = "https://localhost:8080"
}

output "argocd_admin_password_command" {
  description = "Command to retrieve the initial ArgoCD admin password"
  value       = module.cluster_services.argocd_admin_password_command
}

output "argocd_login_credentials" {
  description = "ArgoCD login information"
  value = {
    username = "admin"
    password = "Retrieve with: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
  }
  sensitive = true
}

# ===============================================================================
# GitOps Repository Information
# ===============================================================================

output "gitops_repository_url" {
  description = "Git repository URL that ArgoCD watches"
  value       = var.argocd_repo_url
}

output "gitops_repository_path" {
  description = "Path within Git repository where ArgoCD applications are defined"
  value       = var.argocd_repo_path
}

output "gitops_target_branch" {
  description = "Git branch that ArgoCD syncs from"
  value       = var.argocd_target_revision
}

# ===============================================================================
# NGINX Ingress Controller Information
# ===============================================================================

output "nginx_controller_service_command" {
  description = "Command to get NGINX LoadBalancer external IP/hostname"
  value       = "kubectl -n ingress-nginx get svc ingress-nginx-controller -o wide"
}

output "nginx_controller_info" {
  description = "Information about NGINX Ingress Controller"
  value = {
    namespace    = "ingress-nginx"
    chart        = "ingress-nginx"
    version      = "4.10.0"
    service_type = "LoadBalancer"
  }
}

# ===============================================================================
# Bootstrap Services Summary
# ===============================================================================

output "bootstrap_services_summary" {
  description = "Summary of all bootstrap services"
  value = {
    nginx_ingress = {
      status       = "✅ Provisioned by Terraform"
      purpose      = "Routes HTTP traffic to services (with /argo path-based routing)"
      namespace    = module.cluster_services.nginx_ingress_namespace
      service_type = "LoadBalancer (AWS NLB)"
      access_cmd   = module.cluster_services.nginx_loadbalancer_command
    }
    argocd = {
      status         = "✅ Provisioned by Terraform + ArgoCD App-of-Apps seeded"
      purpose        = "Continuous deployment from Git (GitOps)"
      namespace      = module.cluster_services.argocd_namespace
      replicas       = "2 (HA)"
      access_url     = module.cluster_services.argocd_url
      admin_password = module.cluster_services.argocd_admin_password_command
    }
  }
}
