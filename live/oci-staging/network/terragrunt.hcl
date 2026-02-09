# OCI Staging - Network Module
# Creates VCN, subnets, gateways, and security rules

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path   = "../env.hcl"
  expose = true
}

terraform {
  source = "${get_repo_root()}/modules/oci-network"
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
  # Identity
  tenancy_ocid   = include.env.locals.tenancy_ocid
  compartment_id = include.env.locals.compartment_id
  region         = include.env.locals.region

  # Naming
  cluster_name = include.env.locals.cluster_name

  # Network CIDRs
  vcn_cidr            = include.env.locals.vcn_cidr
  public_subnet_cidr  = include.env.locals.public_subnet_cidr
  private_subnet_cidr = include.env.locals.private_subnet_cidr

  # Traffic rules
  allow_http             = true
  allow_https            = true
  ssh_allowed_cidrs      = ["93.173.65.64/32", "10.0.20.0/24"] # Allow SSH from your IP and bastion/private subnet
  enable_nodeport_access = true
  k8s_api_allowed_cidrs  = ["10.0.0.0/16"] # Allow VCN CIDR to access K8s API

  # Feature flags - KEEP FALSE FOR ALWAYS FREE
  enable_nat_gateway     = include.env.locals.enable_nat_gateway
  enable_service_gateway = include.env.locals.enable_service_gateway
  enable_ipv6            = false

  # Tags
  common_tags = include.env.locals.common_tags
}
