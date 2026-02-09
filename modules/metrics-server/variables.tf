# Metrics Server Module Variables

variable "platform" {
  description = "Kubernetes platform: kind, oke, eks"
  type        = string
  
  validation {
    condition     = contains(["kind", "oke", "eks"], var.platform)
    error_message = "Platform must be one of: kind, oke, eks."
  }
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
}

variable "kube_context" {
  description = "Kubernetes context name (auto-generated if empty)"
  type        = string
  default     = ""
}

variable "namespace" {
  description = "Namespace for metrics-server (usually kube-system)"
  type        = string
  default     = "kube-system"
}

variable "use_helm" {
  description = "Install using Helm chart (true) or raw manifest (false)"
  type        = bool
  default     = false
}

variable "helm_version" {
  description = "Version of metrics-server Helm chart"
  type        = string
  default     = "3.12.0"
}

variable "cluster_trigger_id" {
  description = "Cluster resource ID to trigger reinstall on cluster recreation"
  type        = string
  default     = ""
}
