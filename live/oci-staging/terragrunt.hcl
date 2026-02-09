# OCI Staging Environment - Root Terragrunt Configuration
# Inherits from root.hcl and sets up OCI-specific providers

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env = read_terragrunt_config("${get_terragrunt_dir()}/env.hcl").locals
}

# Generate OCI provider configuration
generate "oci_provider" {
  path      = "oci_provider.tf"
  if_exists = "overwrite"
  contents  = <<-EOF
    terraform {
      required_providers {
        oci = {
          source  = "oracle/oci"
          version = "~> 5.0"
        }
        kubernetes = {
          source  = "hashicorp/kubernetes"
          version = "~> 2.20"
        }
        helm = {
          source  = "hashicorp/helm"
          version = "~> 2.10"
        }
      }
    }

    provider "oci" {
      tenancy_ocid     = "${local.env.tenancy_ocid}"
      user_ocid        = "${local.env.user_ocid}"
      fingerprint      = "${local.env.fingerprint}"
      private_key_path = "${local.env.private_key_path}"
      region           = "${local.env.region}"
    }
  EOF
}
