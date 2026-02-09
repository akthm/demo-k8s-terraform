################################################################################
# OCI Block Volume StorageClass Module - Variables
################################################################################

variable "storage_class_name" {
  description = "Name of the storage class"
  type        = string
  default     = "oci-bv"
}

variable "is_default" {
  description = "Set as the default storage class"
  type        = bool
  default     = true
}

variable "vpus_per_gb" {
  description = "Volume Performance Units per GB. 0=Lower Cost, 10=Balanced, 20=Higher Performance"
  type        = number
  default     = 10

  validation {
    condition     = contains([0, 10, 20], var.vpus_per_gb)
    error_message = "vpus_per_gb must be 0 (Lower Cost), 10 (Balanced), or 20 (Higher Performance)."
  }
}

variable "attachment_type" {
  description = "Block volume attachment type"
  type        = string
  default     = "paravirtualized"

  validation {
    condition     = contains(["paravirtualized", "iscsi"], var.attachment_type)
    error_message = "Attachment type must be 'paravirtualized' or 'iscsi'."
  }
}

variable "reclaim_policy" {
  description = "Reclaim policy for the storage class"
  type        = string
  default     = "Delete"

  validation {
    condition     = contains(["Delete", "Retain"], var.reclaim_policy)
    error_message = "Reclaim policy must be 'Delete' or 'Retain'."
  }
}

variable "volume_binding_mode" {
  description = "Volume binding mode"
  type        = string
  default     = "WaitForFirstConsumer"

  validation {
    condition     = contains(["Immediate", "WaitForFirstConsumer"], var.volume_binding_mode)
    error_message = "Volume binding mode must be 'Immediate' or 'WaitForFirstConsumer'."
  }
}

variable "allow_expansion" {
  description = "Allow volume expansion"
  type        = bool
  default     = true
}

variable "create_high_perf_class" {
  description = "Create an additional high-performance storage class"
  type        = bool
  default     = false
}

variable "create_balanced_class" {
  description = "Create an additional balanced storage class"
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels to apply to storage classes"
  type        = map(string)
  default = {
    "app.kubernetes.io/managed-by" = "terraform"
    "storage.oci.oraclecloud.com"  = "block-volume"
  }
}
