# Terragrunt configuration for MetalLB LoadBalancer

# Include the root configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Include environment configuration
include "env" {
  path   = "../env.hcl"
  expose = true
}

# Configure the Terraform module source
terraform {
  source = "../../../modules/metallb"
}

# Dependency on KIND cluster
dependency "kind" {
  config_path = "../kind"

  mock_outputs = {
    cluster_name    = "local-dev"
    kube_context    = "kind-local-dev"
    kubeconfig_path = "~/.kube/config"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

# Generate provider configuration
generate "provider_override" {
  path      = "provider_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "helm" {
  kubernetes {
    config_path    = "${dependency.kind.outputs.kubeconfig_path}"
    config_context = "${dependency.kind.outputs.kube_context}"
  }
}

provider "kubectl" {
  config_path    = "${dependency.kind.outputs.kubeconfig_path}"
  config_context = "${dependency.kind.outputs.kube_context}"
}
EOF
}

# Module inputs
inputs = {
  kubeconfig_path = dependency.kind.outputs.kubeconfig_path

  # MetalLB IP address pool - must be within Docker Kind network range
  # Get Docker network CIDR: docker network inspect kind | jq '.[0].IPAM.Config[0].Subnet'
  ip_address_pool = {
    name      = "default"
    protocol  = "layer2"
    addresses = ["172.18.255.200-172.18.255.250"]
  }

  metallb_version = "0.14.5"
}
