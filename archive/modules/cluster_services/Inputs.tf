variable "cluster_name" {
  description = "The name of the EKS cluster."
  type        = string
}

variable "cluster_endpoint" {
  description = "The API endpoint for the EKS cluster."
  type        = string
}

variable "cluster_certificate_authority_data" {
  description = "The base64 encoded certificate authority data for the EKS cluster."
  type        = string
}

variable "cluster_oidc_issuer_url" {
  description = "The OIDC issuer URL for the EKS cluster. Used for IRSA."
  type        = string
}

variable "cluster_oidc_provider_arn" {
  description = "The ARN of the OIDC provider for the EKS cluster. Used for IRSA."
  type        = string
}

variable "aws_region" {
  description = "The AWS region where the cluster and resources are."
  type        = string
}

variable "argocd_app_of_apps_repo_url" {
  description = "The Git repository URL for the ArgoCD 'App of Apps' to watch."
  type        = string
  default     = "https.github.com/your-org/your-k8s-apps"
}

variable "argocd_app_of_apps_repo_path" {
  description = "The path within the Git repo for the 'App of Apps' to watch."
  type        = string
  default     = "apps/staging"
}