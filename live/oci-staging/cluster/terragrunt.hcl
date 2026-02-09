# OCI Staging - OKE Cluster Module
# Creates OKE control plane (BASIC_CLUSTER = Always Free)

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
    vcn_id           = "ocid1.vcn.oc1.mock"
    public_subnet_id = "ocid1.subnet.oc1.mock.public"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

terraform {
  source = "${get_repo_root()}/modules/oke-cluster"
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

  # Cluster configuration
  cluster_name       = include.env.locals.cluster_name
  kubernetes_version = include.env.locals.kubernetes_version
  vcn_id             = dependency.network.outputs.vcn_id

  # CRITICAL: Use BASIC_CLUSTER to avoid control plane fees
  cluster_type = "BASIC_CLUSTER"

  # Network
  cni_type           = "FLANNEL_OVERLAY"
  endpoint_public    = true
  endpoint_subnet_id = dependency.network.outputs.public_subnet_id

  # Kubernetes network CIDRs
  pods_cidr     = "10.244.0.0/16"
  services_cidr = "10.96.0.0/16"

  # Service LB subnets (use public for any LB services)
  service_lb_subnet_ids = [dependency.network.outputs.public_subnet_id]

  # Dashboard (deprecated, keep disabled)
  enable_dashboard = false

  # Tags
  common_tags = include.env.locals.common_tags
}
