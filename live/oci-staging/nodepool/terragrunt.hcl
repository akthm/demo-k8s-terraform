# OCI Staging - OKE Node Pool Module
# Creates worker nodes (Always Free: 2x A1.Flex with 2 OCPU / 12GB each)

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
    private_subnet_id    = "ocid1.subnet.oc1.mock.private"
    availability_domains = ["AD-1"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "cluster" {
  config_path = "../cluster"

  mock_outputs = {
    cluster_id                 = "ocid1.cluster.oc1.mock"
    cluster_kubernetes_version = "v1.34.1"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

terraform {
  source = "${get_repo_root()}/modules/oke-nodepool"
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

  # Cluster reference
  cluster_id         = dependency.cluster.outputs.cluster_id
  kubernetes_version = dependency.cluster.outputs.cluster_kubernetes_version
  node_pool_name     = include.env.locals.cluster_name

  # Worker configuration - ALWAYS FREE OPTIMIZED
  worker_count          = include.env.locals.worker_count       # 1
  worker_shape          = include.env.locals.worker_shape       # VM.Standard.A1.Flex
  worker_ocpus          = include.env.locals.worker_ocpus       # 4 per node
  worker_memory_gb      = include.env.locals.worker_memory_gb   # 24 per node
  worker_boot_volume_gb = include.env.locals.worker_boot_volume_gb # 50 per node

  # Network - Using private subnet with Service Gateway (FREE) for OCI service access
  node_subnet_id      = dependency.network.outputs.private_subnet_id
  availability_domain = dependency.network.outputs.availability_domains[0]
  cni_type            = "FLANNEL_OVERLAY"

  # Node image (leave empty for latest OKE image)
  node_image_id  = ""
  node_os_version = "8"

  # SSH access (via Bastion)
  ssh_public_key = include.env.locals.ssh_public_key

  # Labels
  node_labels = {
    "node-type"   = "worker"
    "tier"        = "always-free"
    "environment" = "staging"
  }

  # Tags
  common_tags = include.env.locals.common_tags
}
