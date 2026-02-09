################################################################################
# OCI Edge Proxy Module - Variables
################################################################################

variable "tenancy_ocid" {
  description = "The OCID of the tenancy"
  type        = string
}

variable "compartment_id" {
  description = "The OCID of the compartment"
  type        = string
}

# Feature flag
variable "enable_edge_proxy" {
  description = "Enable the edge proxy VM (recommended for Always Free ingress)"
  type        = bool
  default     = true
}

# Naming
variable "edge_name" {
  description = "Name for the edge proxy instance"
  type        = string
  default     = "edge-proxy"
}

# Compute shape - Always Free
variable "edge_shape" {
  description = "Compute shape for edge proxy. VM.Standard.E2.1.Micro is Always Free."
  type        = string
  default     = "VM.Standard.E2.1.Micro"
}

variable "edge_boot_volume_gb" {
  description = "Boot volume size in GB for edge proxy"
  type        = number
  default     = 50

  validation {
    condition     = var.edge_boot_volume_gb >= 47 && var.edge_boot_volume_gb <= 50
    error_message = "Boot volume should be 47-50 GB for E2.1.Micro Always Free."
  }
}

variable "os_version" {
  description = "Oracle Linux version"
  type        = string
  default     = "8"
}

# Network
variable "public_subnet_id" {
  description = "The OCID of the public subnet for the edge proxy"
  type        = string
}

variable "assign_public_ip" {
  description = "Assign an ephemeral public IP to the edge proxy"
  type        = bool
  default     = true
}

variable "use_reserved_ip" {
  description = "Use a reserved (static) public IP instead of ephemeral"
  type        = bool
  default     = false
}

# Backend configuration (Kubernetes worker nodes)
variable "backend_ips" {
  description = "List of private IPs of Kubernetes worker nodes"
  type        = list(string)
  default     = []
}

variable "ingress_http_nodeport" {
  description = "NodePort for HTTP traffic on Ingress Controller"
  type        = number
  default     = 30080
}

variable "ingress_https_nodeport" {
  description = "NodePort for HTTPS traffic on Ingress Controller"
  type        = number
  default     = 30443
}

# Access
variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
  default     = ""
}

# Tags
variable "common_tags" {
  description = "Freeform tags to apply"
  type        = map(string)
  default     = {}
}
