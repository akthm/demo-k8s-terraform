# OCI Autonomous Database Module Variables

variable "compartment_id" {
  description = "OCID of the compartment where ATP will be created"
  type        = string
}

variable "vcn_id" {
  description = "OCID of the VCN"
  type        = string
}

variable "private_subnet_id" {
  description = "OCID of the private subnet for ATP private endpoint"
  type        = string
}

variable "worker_subnet_cidr" {
  description = "CIDR block of worker subnet (for NSG ingress rules)"
  type        = string
}

variable "db_name" {
  description = "Database name (alphanumeric, max 14 chars)"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{0,13}$", var.db_name))
    error_message = "Database name must start with a letter and contain only alphanumeric characters (max 14 chars)."
  }
}

variable "display_name" {
  description = "Display name for the database"
  type        = string
  default     = ""
}

variable "db_workload" {
  description = "Database workload type: OLTP or DW"
  type        = string
  default     = "OLTP"
  
  validation {
    condition     = contains(["OLTP", "DW"], var.db_workload)
    error_message = "Workload must be OLTP or DW."
  }
}

variable "admin_password" {
  description = "Admin password for the database (12-30 chars, 2 uppercase, 2 lowercase, 2 numbers, 2 special)"
  type        = string
  sensitive   = true
  
  validation {
    condition     = length(var.admin_password) >= 12 && length(var.admin_password) <= 30
    error_message = "Password must be between 12 and 30 characters."
  }
}

variable "is_free_tier" {
  description = "Whether to use Always Free tier (limits: 1 OCPU, 20GB storage)"
  type        = bool
  default     = true
}

variable "cpu_core_count" {
  description = "Number of CPU cores (ignored if is_free_tier=true)"
  type        = number
  default     = 1
}

variable "data_storage_size_in_tbs" {
  description = "Storage size in TB (ignored if is_free_tier=true)"
  type        = number
  default     = 1
}

variable "require_mtls" {
  description = "Require mTLS with wallet (set false for TLS-only private endpoint access)"
  type        = bool
  default     = false
}

variable "license_model" {
  description = "License model: LICENSE_INCLUDED or BRING_YOUR_OWN_LICENSE"
  type        = string
  default     = "LICENSE_INCLUDED"
}

variable "is_auto_scaling_enabled" {
  description = "Enable auto-scaling (not available for Always Free tier)"
  type        = bool
  default     = false
}

variable "database_users" {
  description = "List of database users to create (placeholder - actual creation via SQL)"
  type = list(object({
    username = string
    password = string
  }))
  default   = []
  sensitive = true
}

variable "whitelisted_ips" {
  description = "List of whitelisted IPs/CIDRs for public endpoint access (Always Free only)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Freeform tags to apply to all resources"
  type        = map(string)
  default     = {}
}
