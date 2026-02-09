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
  type        = string
  default     = "eks" # "eks" | "kind" | "oke"
  description = "Target platform: eks (AWS), kind (local), or oke (OCI)"

  validation {
    condition     = contains(["eks", "kind", "oke"], var.platform)
    error_message = "Platform must be 'eks', 'kind', or 'oke'."
  }
}

variable "use_metallb" {
  description = "Use MetalLB LoadBalancer for Kind cluster (requires MetalLB to be installed)"
  type        = bool
  default     = false
}

variable "ingress_domain" {
  description = "Base domain for ingress (e.g., platform.172.18.255.200.nip.io)"
  type        = string
  default     = "localhost"
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
  default     = "9.2.3"
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
  default     = ""
}

# ===============================================================================
# OKE-Specific Configuration
# ===============================================================================

variable "nginx_service_type" {
  description = "NGINX Ingress Controller service type (LoadBalancer, NodePort, ClusterIP)"
  type        = string
  default     = "LoadBalancer"
}

variable "nginx_http_nodeport" {
  description = "NodePort for HTTP when using NodePort service type"
  type        = number
  default     = 30080
}

variable "nginx_https_nodeport" {
  description = "NodePort for HTTPS when using NodePort service type"
  type        = number
  default     = 30443
}

variable "install_argocd" {
  description = "Install ArgoCD"
  type        = bool
  default     = true
}

variable "install_nginx_ingress" {
  description = "Install NGINX Ingress Controller"
  type        = bool
  default     = true
}

variable "install_cert_manager" {
  description = "Install cert-manager for TLS certificate management"
  type        = bool
  default     = false
}

variable "install_external_secrets" {
  description = "Install External Secrets Operator"
  type        = bool
  default     = false
}

variable "argocd_namespace" {
  description = "Namespace for ArgoCD installation"
  type        = string
  default     = "argocd"
}

variable "cert_manager_email" {
  description = "Email address for Let's Encrypt certificate registration"
  type        = string
  default     = "admin@example.com"
}

variable "oci_vault_id" {
  description = "OCID of OCI Vault for External Secrets Operator (OKE only)"
  type        = string
  default     = ""
}

variable "oci_region" {
  description = "OCI region for vault access (e.g., il-jerusalem-1)"
  type        = string
  default     = ""
}

variable "cluster_trigger_id" {
  description = "Cluster resource ID to trigger metrics-server reinstall on cluster recreation"
  type        = string
  default     = ""
}
