# ==============================================================================
# Cluster Services Module - Input Variables (Simplified)
# ==============================================================================

variable "environment" {
  type = string
}

variable "owner" {
  type        = string
  description = "Owner used for labels/naming (NOT a secret)."
}

variable "app_name" {
  type        = string
  description = "App name used for labels/naming (NOT a secret)."
}

variable "common_tags" {
  type        = map(string)
  description = "AWS tags (standard keys: owner/app_name/environment/managed_by)."
  default     = {}
}

# ===============================================================================
# LOCAL VS CLOUD PLATFORM SWITCH
# ===============================================================================

variable "platform" {
  type    = string
  default = "eks" # "eks" | "kind"
}


# ===============================================================================
# EKS Cluster Information
# ===============================================================================

variable "cluster_name" {
  description = "The name of the EKS cluster"
  type        = string
}

variable "cluster_endpoint" {
  description = "The API endpoint for the EKS cluster"
  type        = string
}

variable "cluster_certificate_authority_data" {
  description = "The base64 encoded certificate authority data for the EKS cluster"
  type        = string
}

# ===============================================================================
# ArgoCD Configuration
# ===============================================================================

variable "argocd_version" {
  description = "Helm chart version for ArgoCD"
  type        = string
  default     = "6.0.0"
}

variable "argocd_repo_url" {
  description = "Git repository URL for ArgoCD App-of-Apps pattern"
  type        = string
}

variable "argocd_repo_path" {
  description = "Path within Git repo for App-of-Apps manifests"
  type        = string
  default     = "apps"
}

variable "argocd_target_revision" {
  description = "Git branch or tag for ArgoCD to sync"
  type        = string
  default     = "main"
}

variable "git_token" {
  description = "GitHub/GitLab personal access token for private repository access"
  type        = string
  sensitive   = true
}
