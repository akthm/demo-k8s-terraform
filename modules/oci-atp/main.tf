# OCI Autonomous Database Module
# Creates ATP with TLS-only private endpoint (no wallet required)

terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
  }
}

# Network Security Group for ATP
resource "oci_core_network_security_group" "atp" {
  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id
  display_name   = "${var.db_name}-nsg"

  freeform_tags = var.tags
}

# Allow ingress from worker subnet to ATP
resource "oci_core_network_security_group_security_rule" "atp_ingress" {
  network_security_group_id = oci_core_network_security_group.atp.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = var.worker_subnet_cidr
  source_type               = "CIDR_BLOCK"
  stateless                 = false

  tcp_options {
    destination_port_range {
      min = 1521
      max = 1522
    }
  }
}

# Allow egress from ATP to worker subnet (for responses)
resource "oci_core_network_security_group_security_rule" "atp_egress" {
  network_security_group_id = oci_core_network_security_group.atp.id
  direction                 = "EGRESS"
  protocol                  = "6" # TCP
  destination               = var.worker_subnet_cidr
  destination_type          = "CIDR_BLOCK"
  stateless                 = false
}

# Autonomous Database
resource "oci_database_autonomous_database" "main" {
  compartment_id = var.compartment_id
  db_name        = var.db_name
  display_name   = var.display_name != "" ? var.display_name : var.db_name
  
  # Workload type
  db_workload = var.db_workload
  
  # Always Free tier configuration
  is_free_tier           = var.is_free_tier
  cpu_core_count         = var.is_free_tier ? 1 : var.cpu_core_count
  data_storage_size_in_tbs = var.is_free_tier ? 1 : var.data_storage_size_in_tbs
  
  # Admin credentials
  admin_password = var.admin_password
  
  # Private endpoint configuration (only for PAID tier)
  # Always Free ATP CANNOT use private endpoints
  subnet_id = var.is_free_tier ? null : var.private_subnet_id
  nsg_ids   = var.is_free_tier ? null : [oci_core_network_security_group.atp.id]
  
  # Public endpoint access control (for Always Free)
  # IP whitelist to restrict access to specific IPs/CIDRs
  whitelisted_ips = var.is_free_tier ? var.whitelisted_ips : null
  
  # CRITICAL: Disable mTLS for TLS-only connections (no wallet needed)
  is_mtls_connection_required = var.require_mtls
  
  # License
  license_model = var.license_model
  
  # Auto-scaling (not available for Always Free)
  is_auto_scaling_enabled = var.is_free_tier ? false : var.is_auto_scaling_enabled
  
  # Backup configuration
  is_auto_scaling_for_storage_enabled = false
  
  freeform_tags = var.tags

  lifecycle {
    ignore_changes = [
      admin_password, # Don't update password on every apply
      cpu_core_count  # Always Free tier manages this automatically, can fluctuate between 0 and 1
    ]
  }
}

# Database users (created via SQL after ATP is provisioned)
# Note: This is a placeholder - actual user creation should be done via null_resource with SQL
resource "null_resource" "create_db_users" {
  count = length(var.database_users) > 0 ? 1 : 0

  triggers = {
    users = jsonencode(var.database_users)
  }

  # This would require OCI Cloud Shell or bastion access with SQL*Plus
  # For now, users should be created manually or via CI/CD
  provisioner "local-exec" {
    command = "echo 'Database users should be created via SQL: ${jsonencode(var.database_users)}'"
  }

  depends_on = [oci_database_autonomous_database.main]
}
