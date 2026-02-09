# OCI Staging - Edge Proxy Module
# Always Free E2.1.Micro VM as NGINX reverse proxy for public ingress

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

# Note: In production, you would get the worker node IPs after nodepool creation
# For now, we'll set placeholder IPs that can be updated after deployment

terraform {
  source = "${get_repo_root()}/modules/oci-edge-proxy"
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

  # Feature flag
  enable_edge_proxy = include.env.locals.enable_edge_proxy

  # Naming
  edge_name = "${include.env.locals.cluster_name}-edge-proxy"

  # Compute - Always Free
  edge_shape          = "VM.Standard.E2.1.Micro"
  edge_boot_volume_gb = 50
  os_version          = "8"

  # Network
  public_subnet_id = dependency.network.outputs.public_subnet_id
  assign_public_ip = true
  use_reserved_ip  = false # Set to true for stable DNS

  # Backend configuration (Kubernetes worker nodes)
  # Dynamically populated from nodepool outputs
  backend_ips = dependency.nodepool.outputs.node_private_ips

  # NGINX ingress NodePorts (must match cluster-services config)
  ingress_http_nodeport  = 30080
  ingress_https_nodeport = 30443

  # SSH access
  ssh_public_key = include.env.locals.ssh_public_key

  # Tags
  common_tags = include.env.locals.common_tags
}
