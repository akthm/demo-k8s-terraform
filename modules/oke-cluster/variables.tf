################################################################################
# OKE Cluster Module - Variables
################################################################################

variable "compartment_id" {
  description = "The OCID of the compartment for the OKE cluster"
  type        = string
}

variable "cluster_name" {
  description = "Name of the OKE cluster"
  type        = string
}

variable "vcn_id" {
  description = "The OCID of the VCN for the cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the cluster"
  type        = string
}

variable "cluster_type" {
  description = "OKE cluster type. Use BASIC_CLUSTER (free) or ENHANCED_CLUSTER (paid)"
  type        = string
  default     = "BASIC_CLUSTER"

  validation {
    condition     = contains(["BASIC_CLUSTER", "ENHANCED_CLUSTER"], var.cluster_type)
    error_message = "Cluster type must be BASIC_CLUSTER or ENHANCED_CLUSTER. Use BASIC_CLUSTER to stay free."
  }
}

variable "cni_type" {
  description = "CNI type for pod networking (FLANNEL_OVERLAY or OCI_VCN_IP_NATIVE)"
  type        = string
  default     = "FLANNEL_OVERLAY"

  validation {
    condition     = contains(["FLANNEL_OVERLAY", "OCI_VCN_IP_NATIVE"], var.cni_type)
    error_message = "CNI type must be FLANNEL_OVERLAY or OCI_VCN_IP_NATIVE."
  }
}

variable "endpoint_public" {
  description = "Whether the Kubernetes API endpoint should be publicly accessible"
  type        = bool
  default     = true
}

variable "endpoint_subnet_id" {
  description = "The OCID of the subnet for the Kubernetes API endpoint"
  type        = string
}

variable "pods_cidr" {
  description = "CIDR block for Kubernetes pods"
  type        = string
  default     = "10.244.0.0/16"
}

variable "services_cidr" {
  description = "CIDR block for Kubernetes services"
  type        = string
  default     = "10.96.0.0/16"
}

variable "service_lb_subnet_ids" {
  description = "List of subnet OCIDs for service load balancers"
  type        = list(string)
  default     = []
}

variable "enable_dashboard" {
  description = "Enable Kubernetes Dashboard (deprecated, usually false)"
  type        = bool
  default     = false
}

variable "common_tags" {
  description = "Freeform tags to apply to the cluster"
  type        = map(string)
  default     = {}
}
