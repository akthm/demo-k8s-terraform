# Terragrunt configuration for KIND cluster module

# Include the root configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Include environment configuration
include "env" {
  path = "../env.hcl"
  expose = true
}

# Configure the Terraform module source
terraform {
  source = "../../../modules/kind-cluster"
}

# Module-specific inputs
inputs = {
  cluster_name     = "local-dev"
  kind_config_path = "${get_terragrunt_dir()}/../../../modules/kind-cluster/kind-config.yaml"
}
