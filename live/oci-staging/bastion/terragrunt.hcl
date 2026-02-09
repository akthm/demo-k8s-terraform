# OCI Staging - Bastion Module
# Managed OCI Bastion for secure SSH access to private nodes

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path   = "../env.hcl"
  expose = true
}

dependency "network" {
  config_path = "../network"

  mock_outputs = {
    private_subnet_id = "ocid1.subnet.oc1.mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

terraform {
  source = "${get_repo_root()}/modules/oci-bastion"
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

  # Bastion configuration
  bastion_name     = "${include.env.locals.cluster_name}-bastion"
  target_subnet_id = dependency.network.outputs.private_subnet_id
  allowed_cidrs    = include.env.locals.bastion_allowed_cidrs
  max_session_ttl  = 10800 # 3 hours

  # Tags
  common_tags = include.env.locals.common_tags
}
