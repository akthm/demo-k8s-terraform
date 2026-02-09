# OCI Staging - Network Load Balancer
# Always Free tier load balancer for routing to Kubernetes NodePorts

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
    public_subnet_id = "ocid1.subnet.oc1.mock.public"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "nodepool" {
  config_path = "../nodepool"
  
  mock_outputs = {
    node_private_ips = []
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

terraform {
  source = "${get_repo_root()}/modules/oci-network-lb"
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
  compartment_id = include.env.locals.compartment_id

  # Naming
  lb_name = "${include.env.locals.cluster_name}-nlb"

  # Network
  public_subnet_id = dependency.network.outputs.public_subnet_id

  # Backend configuration (dynamically from nodepool)
  backend_ips = dependency.nodepool.outputs.node_private_ips

  # NodePort configuration (must match cluster-services)
  http_nodeport  = 30080
  https_nodeport = 30443

  # Reserved IP (set to actual OCID if you want stable IP, or leave empty for ephemeral)
  reserved_ip_id = ""

  # Tags
  common_tags = include.env.locals.common_tags
}
