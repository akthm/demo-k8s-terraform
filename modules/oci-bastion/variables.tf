################################################################################
# OCI Bastion Module - Variables
################################################################################

variable "compartment_id" {
  description = "The OCID of the compartment where the bastion will be created"
  type        = string
}

variable "bastion_name" {
  description = "Name for the bastion resource"
  type        = string
}

variable "target_subnet_id" {
  description = "The OCID of the subnet that the bastion connects to (typically the private subnet)"
  type        = string
}

variable "allowed_cidrs" {
  description = "List of CIDRs allowed to connect to the bastion (your office/home IPs)"
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.allowed_cidrs) > 0
    error_message = "At least one allowed CIDR must be specified."
  }
}

variable "max_session_ttl" {
  description = "Maximum session time-to-live in seconds (default 3 hours = 10800)"
  type        = number
  default     = 10800

  validation {
    condition     = var.max_session_ttl >= 1800 && var.max_session_ttl <= 10800
    error_message = "Session TTL must be between 1800 (30 min) and 10800 (3 hours) seconds."
  }
}

variable "common_tags" {
  description = "Freeform tags to apply to the bastion"
  type        = map(string)
  default     = {}
}
