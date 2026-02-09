################################################################################
# OKE Node Pool Module - Variables
################################################################################

variable "compartment_id" {
  description = "The OCID of the compartment for the node pool"
  type        = string
}

variable "cluster_id" {
  description = "The OCID of the OKE cluster"
  type        = string
}

variable "node_pool_name" {
  description = "Name prefix for the node pool"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the nodes (should match cluster)"
  type        = string
  default     = "v1.28.2"
}

# Worker node configuration - Always Free optimized
variable "worker_count" {
  description = "Number of worker nodes (Always Free max: 2 with A1.Flex)"
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 4
    error_message = "Worker count must be between 1 and 4."
  }
}

variable "worker_shape" {
  description = "Compute shape for worker nodes. VM.Standard.A1.Flex is Always Free eligible."
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "worker_ocpus" {
  description = "Number of OCPUs per worker (Always Free total: 4 OCPUs across all A1 instances)"
  type        = number
  default     = 2

  validation {
    condition     = var.worker_ocpus >= 1 && var.worker_ocpus <= 4
    error_message = "OCPUs per worker must be between 1 and 4."
  }
}

variable "worker_memory_gb" {
  description = "Memory in GB per worker (Always Free total: 24 GB across all A1 instances)"
  type        = number
  default     = 12

  validation {
    condition     = var.worker_memory_gb >= 1 && var.worker_memory_gb <= 24
    error_message = "Memory per worker must be between 1 and 24 GB."
  }
}

variable "worker_boot_volume_gb" {
  description = "Boot volume size in GB per worker (Always Free total: 200 GB)"
  type        = number
  default     = 50

  validation {
    condition     = var.worker_boot_volume_gb >= 50 && var.worker_boot_volume_gb <= 100
    error_message = "Boot volume must be between 50 and 100 GB to stay within limits."
  }
}

# Network configuration
variable "node_subnet_id" {
  description = "The OCID of the subnet for worker nodes (should be private)"
  type        = string
}

variable "availability_domain" {
  description = "Availability domain for node placement (Jerusalem has 1 AD)"
  type        = string
}

variable "cni_type" {
  description = "CNI type for pod networking (FLANNEL_OVERLAY or OCI_VCN_IP_NATIVE)"
  type        = string
  default     = "FLANNEL_OVERLAY"
}

# Node image
variable "node_image_id" {
  description = "Specific image OCID for nodes. Leave empty to use latest OKE image."
  type        = string
  default     = ""
}

variable "node_os_version" {
  description = "Oracle Linux version for nodes"
  type        = string
  default     = "8"
}

# Access
variable "ssh_public_key" {
  description = "SSH public key for node access (use with Bastion)"
  type        = string
  default     = ""
}

# Labels and tags
variable "node_labels" {
  description = "Kubernetes labels to apply to nodes"
  type        = map(string)
  default = {
    "node-type" = "worker"
    "tier"      = "always-free"
  }
}

variable "common_tags" {
  description = "Freeform tags to apply to the node pool"
  type        = map(string)
  default     = {}
}

# Security
variable "enable_pv_encryption" {
  description = "Enable in-transit encryption for persistent volumes"
  type        = bool
  default     = true
}
