# ==============================================================================
# OCI Object Storage Bucket for ATP Wallets
# ==============================================================================

variable "compartment_id" {
  description = "OCI Compartment OCID"
  type        = string
}

variable "bucket_name" {
  description = "Name of the Object Storage bucket"
  type        = string
}

variable "namespace" {
  description = "Object Storage namespace (tenancy name)"
  type        = string
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

# Object Storage Bucket
resource "oci_objectstorage_bucket" "wallet_bucket" {
  compartment_id = var.compartment_id
  namespace      = var.namespace
  name           = var.bucket_name
  access_type    = "NoPublicAccess"  # Private bucket
  
  # Enable versioning for rotation history
  versioning = "Enabled"
  
  # Free tier uses Standard storage tier
  storage_tier = "Standard"
  
  # Auto-tiering disabled for free tier simplicity
  auto_tiering = "Disabled"
  
  freeform_tags = var.common_tags
}

# Lifecycle Policy - Retain only last 3 wallet versions
# NOTE: Requires additional IAM permissions for object storage service principal
# Commenting out for initial deployment - can be enabled later if needed
# resource "oci_objectstorage_object_lifecycle_policy" "wallet_retention" {
#   namespace = var.namespace
#   bucket    = oci_objectstorage_bucket.wallet_bucket.name
#   
#   rules {
#     action      = "DELETE"
#     is_enabled  = true
#     name        = "retain-last-3-versions"
#     target      = "previous-object-versions"
#     
#     object_name_filter {
#       inclusion_prefixes = ["*_wallet.zip"]
#     }
#     
#     time_amount = 3
#     time_unit   = "DAYS"
#   }
# }

# Outputs
output "bucket_name" {
  description = "Name of the wallet bucket"
  value       = oci_objectstorage_bucket.wallet_bucket.name
}

output "bucket_namespace" {
  description = "Object Storage namespace"
  value       = var.namespace
}

output "bucket_id" {
  description = "Bucket OCID"
  value       = oci_objectstorage_bucket.wallet_bucket.id
}
