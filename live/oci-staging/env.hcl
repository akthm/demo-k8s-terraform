# OCI Staging Environment - env.hcl
# Environment-specific variables for OCI Always Free tier staging cluster
# Region: il-jerusalem-1 (single AD)

locals {
  environment = "oci-staging"
  region      = "il-jerusalem-1"

  # OCI Identity - read from config file or environment variables
  user_ocid        = get_env("TG_VAR_oci_user_ocid", "")
  fingerprint      = get_env("TG_VAR_oci_fingerprint", "")
  private_key_path = get_env("TG_VAR_oci_private_key_path", "~/.oci/oci_api_key.pem")
  private_key_password = get_env("TG_VAR_oci_private_key_password", "")
  
  bastion_ssh_key_path = get_env("TG_VAR_bastion_ssh_key_path", "~/.ssh/oci_staging_key")


  # OCI resource identifiers
  tenancy_ocid   = get_env("TG_VAR_oci_tenancy_ocid", "")
  compartment_id = get_env("TG_VAR_oci_compartment_id", "")
  bastion_ocid   = get_env("TG_VAR_bastion_ocid", "ocid1.bastion.oc1.il-jerusalem-1.amaaaaaa3z7gytyacd3nflem7yf7hg4p4zm72w6ortmfztzrqkmlbgktpc6a")
  # Naming
  owner    = get_env("TG_VAR_owner", "akthmd")
  app_name = get_env("TG_VAR_app_name", "portfolio-platform")
  cluster_name = "oke-staging"

  # Networking - Always Free safe defaults
  vcn_cidr            = "10.0.0.0/16"
  public_subnet_cidr  = "10.0.10.0/24"
  private_subnet_cidr = "10.0.20.0/24"

  # Kubernetes
  kubernetes_version = "v1.34.1"

  # Worker nodes - Always Free optimized (4 OCPU / 24 GB total)
  # Shape options:
  # - VM.Standard.A1.Flex (ARM/Ampere) - preferred but often out of capacity
  # - VM.Standard.E4.Flex (AMD x86) - fallback option
  # Due to capacity constraints, starting with 1 node (can scale to 2 when available)
  worker_count         = 2  # Temporarily 1 node due to capacity constraints
  worker_shape         = "VM.Standard.E3.Flex" # Using AMD due to ARM capacity constraints
  worker_ocpus         = 2  # 4 OCPU on single node (max Always Free)
  worker_memory_gb     = 12 # 24 GB on single node (max Always Free)
  worker_boot_volume_gb = 50 # 50 GB boot volume

  # Feature flags - PAID RESOURCES (keep false for Always Free)
  # NOTE: NAT Gateway required for worker nodes in private subnet (~$33/month)
  # Alternative: Use worker nodes with public IPs in separate public subnet (more complex setup)
  enable_nat_gateway     = true   # REQUIRED for private subnet internet access
  enable_service_gateway = true   # FREE! Allows private subnet to reach OCI services
  enable_edge_proxy      = true  # Uses Always Free E2.1.Micro

# SSH key for node/edge access (for SSH into VMs, NOT for API authentication)
# Generate with: ssh-keygen -t rsa -b 4096 -f ~/.ssh/oci_staging_key
# Then set: export TG_VAR_ssh_public_key="$(cat ~/.ssh/oci_staging_key.pub)"
  ssh_public_key = get_env("TG_VAR_ssh_public_key", "")

  # Bastion allowed CIDRs (your home/office IPs)
  bastion_allowed_cidrs = split(",", get_env("TG_VAR_bastion_allowed_cidrs", "0.0.0.0/0"))

  # Common tags
  common_tags = {
    Environment = "staging"
    Platform    = "oci"
    ManagedBy   = "terragrunt"
    Owner       = local.owner
    AppName     = local.app_name
    FreeTier    = "always-free"
  }
}
