# OCI Staging - ATP Wallet Bucket

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path   = "../env.hcl"
  expose = true
}

terraform {
  source = "${get_repo_root()}/modules/oci-wallet-bucket"
}

# Generate OCI provider configuration
generate "oci_provider" {
  path      = "oci_provider.tf"
  if_exists = "overwrite"
  contents  = <<-EOF
    provider "oci" {
      tenancy_ocid         = "${include.env.locals.tenancy_ocid}"
      user_ocid            = "${include.env.locals.user_ocid}"
      fingerprint          = "${include.env.locals.fingerprint}"
      private_key_path     = "${include.env.locals.private_key_path}"
      private_key_password = "${include.env.locals.private_key_password}"
      region               = "${include.env.locals.region}"
    }
  EOF
}

inputs = {
  compartment_id = include.env.locals.compartment_id
  bucket_name    = "oke-staging-atp-wallets"
  namespace      = "axoq37srkeu5"  # Object Storage namespace (different from tenancy OCID)
  
  common_tags = {
    Environment = "oci-staging"
    ManagedBy   = "terragrunt"
    Purpose     = "atp-wallet-storage"
    Owner       = include.env.locals.owner
  }
}
