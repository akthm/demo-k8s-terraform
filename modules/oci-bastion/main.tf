################################################################################
# OCI Bastion Module - Managed Bastion Service (Always Free)
# Provides secure SSH access to private resources without jump hosts
################################################################################

resource "oci_bastion_bastion" "main" {
  compartment_id               = var.compartment_id
  bastion_type                 = "STANDARD"
  name                         = var.bastion_name
  target_subnet_id             = var.target_subnet_id
  client_cidr_block_allow_list = var.allowed_cidrs

  # Max session TTL in seconds (default 3 hours)
  max_session_ttl_in_seconds = var.max_session_ttl

  freeform_tags = var.common_tags
}
