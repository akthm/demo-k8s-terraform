# OCI Staging - Autonomous Database (ATP) Module
# Creates Always Free ATP with TLS-only private endpoint (no wallet required)

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path   = "../env.hcl"
  expose = true
}

terraform {
  source = "${get_repo_root()}/modules/oci-atp"
}

# Dependency on network module to get VCN and subnet IDs
dependency "network" {
  config_path = "../network"
  
  mock_outputs = {
    vcn_id                 = "ocid1.vcn.mock"
    private_subnet_id      = "ocid1.subnet.mock"
    nat_gateway_public_ip  = "203.0.113.1"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
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
  compartment_id     = include.env.locals.compartment_id
  vcn_id             = dependency.network.outputs.vcn_id
  private_subnet_id  = dependency.network.outputs.private_subnet_id
  worker_subnet_cidr = include.env.locals.private_subnet_cidr
  
  # Database configuration
  db_name      = "stagingdb"
  display_name = "OKE Staging Database"
  db_workload  = "OLTP" # OLTP for transactional workloads, DW for analytics
  
  # Always Free tier - NOTE: Cannot use private endpoints!
  # Always Free ATP only supports public endpoints with IP whitelisting
  is_free_tier           = true
  cpu_core_count         = 1  # Fixed for Always Free
  data_storage_size_in_tbs = 1  # Fixed for Always Free (20GB)
  
  # IP whitelist for public endpoint access (Always Free only)
  # Add your OKE node public IPs, bastion IP, and your office/home IPs
  whitelisted_ips = [
    "${dependency.network.outputs.nat_gateway_public_ip}/32", # NAT Gateway for OKE worker outbound
    # Add more IPs as needed:
    # get_env("TG_VAR_office_public_ip", "203.0.113.0/24"),  # Your office network
    # get_env("TG_VAR_home_public_ip", "198.51.100.5/32"),   # Your home IP
  ]
  
  # Enable mTLS for wallet-based authentication
  # NOTE: Changing from false to true WILL require wallet download and application reconfiguration
  require_mtls = true
  
  # Admin password - CHANGE THIS!
  # Must be 12-30 chars with: 2 uppercase, 2 lowercase, 2 numbers, 2 special
  admin_password = get_env("TG_VAR_atp_admin_password", "ChangeMes123!@")
  
  # License model
  license_model = "LICENSE_INCLUDED"
  
  # Database users (placeholder - actual creation via SQL)
  database_users = [
    {
      username = "flask_user"
      password = get_env("TG_VAR_flask_db_password", "ChangeMeFlask123!@")
    },
    {
      username = "keycloak"
      password = get_env("TG_VAR_keycloak_db_password", "ChangeMeKeycloak123!@")
    }
  ]
  
  tags = {
    Environment = include.env.locals.environment
    ManagedBy   = "terragrunt"
    Owner       = include.env.locals.owner
    Application = include.env.locals.app_name
  }
}
