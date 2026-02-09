################################################################################
# OCI Network Module - Variables
################################################################################

# Identity
variable "tenancy_ocid" {
  description = "The OCID of the tenancy"
  type        = string
}

variable "k8s_api_allowed_cidrs" {
  description = "List of CIDRs allowed to access Kubernetes API"
  type        = list(string)
  default     = []
}

variable "compartment_id" {
  description = "The OCID of the compartment where resources will be created"
  type        = string
}

variable "region" {
  description = "The OCI region (e.g., il-jerusalem-1)"
  type        = string
  default     = "il-jerusalem-1"
}

# Naming
variable "cluster_name" {
  description = "Name prefix for all resources"
  type        = string
}

# Network CIDRs
variable "vcn_cidr" {
  description = "CIDR block for the VCN"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.10.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet (worker nodes)"
  type        = string
  default     = "10.0.20.0/24"
}

# Traffic rules
variable "allow_http" {
  description = "Allow HTTP (port 80) ingress to public subnet"
  type        = bool
  default     = true
}

variable "allow_https" {
  description = "Allow HTTPS (port 443) ingress to public subnet"
  type        = bool
  default     = true
}

variable "ssh_allowed_cidrs" {
  description = "List of CIDRs allowed to SSH to public subnet. Keep empty if using Bastion only."
  type        = list(string)
  default     = []
}

variable "enable_nodeport_access" {
  description = "Allow NodePort range access from public subnet"
  type        = bool
  default     = true
}

variable "nodeport_range_start" {
  description = "Start of NodePort range"
  type        = number
  default     = 30000
}

variable "nodeport_range_end" {
  description = "End of NodePort range"
  type        = number
  default     = 32767
}

# Feature flags (PAID RESOURCES - keep false for Always Free)
variable "enable_nat_gateway" {
  description = "Enable NAT Gateway (PAID RESOURCE - billable)"
  type        = bool
  default     = false
}

variable "enable_service_gateway" {
  description = "Enable Service Gateway for OCI services private access"
  type        = bool
  default     = false
}

variable "enable_ipv6" {
  description = "Enable IPv6 on the VCN"
  type        = bool
  default     = false
}

# Tags
variable "common_tags" {
  description = "Freeform tags to apply to all resources"
  type        = map(string)
  default     = {}
}
