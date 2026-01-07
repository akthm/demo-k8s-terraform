/**
 * ==============================================================================
 * Root Variables - AWS EKS Infrastructure
 * ==============================================================================
 * 
 * All input variables are defined here at the root level.
 * This provides a single source of truth for the entire infrastructure.
 * ==============================================================================
 */

# ===============================================================================
# Common Tags
# ===============================================================================

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type = object({
    owner      = string
    managedBy  = string
    usage      = string
    app_name   = string
  })

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.common_tags.owner))
    error_message = "Owner tag must contain only lowercase alphanumerics and hyphens."
  }
}

# ===============================================================================
# AWS Configuration
# ===============================================================================

variable "region" {
  description = "AWS region where resources will be created"
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-\\d{1}$", var.region))
    error_message = "Region must be a valid AWS region format (e.g., us-east-1)."
  }
}

# ===============================================================================
# Network Configuration
# ===============================================================================

variable "vpc_cidrs" {
  description = "CIDR block for the VPC"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidrs, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "ha" {
  description = "High Availability level - number of availability zones to span"
  type        = number

  validation {
    condition     = var.ha >= 1 && var.ha <= 3
    error_message = "HA value must be between 1 and 3 (AZ count)."
  }
}

# ===============================================================================
# EKS Cluster Configuration
# ===============================================================================

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string

  validation {
    condition     = can(regex("^\\d+\\.\\d{2}$", var.cluster_version))
    error_message = "Cluster version must be in format: X.YY (e.g., 1.31)."
  }
}

variable "node_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z]+$", var.node_type))
    error_message = "Node type must be a valid EC2 instance type (e.g., t3a.medium)."
  }
}

# ===============================================================================
# ArgoCD Configuration
# ===============================================================================

variable "argocd_app_of_apps_repo_url" {
  description = "Git repository URL for ArgoCD 'App of Apps' pattern"
  type        = string

  validation {
    condition     = can(regex("^https://", var.argocd_app_of_apps_repo_url))
    error_message = "Repository URL must start with https:// for secure access."
  }
}

variable "argocd_app_of_apps_repo_path" {
  description = "Path within the Git repository for ArgoCD applications"
  type        = string
  default     = "apps"

  validation {
    condition     = !startswith(var.argocd_app_of_apps_repo_path, "/")
    error_message = "Path must not start with a forward slash."
  }
}
