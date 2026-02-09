# OCI Autonomous Database Module Outputs

output "atp_id" {
  description = "OCID of the Autonomous Database"
  value       = oci_database_autonomous_database.main.id
}

output "atp_display_name" {
  description = "Display name of the database"
  value       = oci_database_autonomous_database.main.display_name
}

output "connection_strings" {
  description = "Connection strings for the database"
  value       = oci_database_autonomous_database.main.connection_strings
  sensitive   = true
}

output "private_endpoint" {
  description = "Private endpoint hostname (null for Always Free public endpoint)"
  value       = oci_database_autonomous_database.main.private_endpoint
}

output "private_endpoint_ip" {
  description = "Private endpoint IP address (null for Always Free public endpoint)"
  value       = oci_database_autonomous_database.main.private_endpoint_ip
}

output "public_endpoint" {
  description = "Public endpoint hostname (for Always Free tier)"
  value       = try(oci_database_autonomous_database.main.connection_strings[0].profiles[0].value, null)
  sensitive   = true
}

output "connection_hostname" {
  description = "Connection hostname (public or private based on tier)"
  value       = var.is_free_tier ? try(oci_database_autonomous_database.main.connection_strings[0].profiles[0].host_format, null) : oci_database_autonomous_database.main.private_endpoint
  sensitive   = true
}

output "connection_urls" {
  description = "Connection URLs by service level"
  value = {
    high   = try(oci_database_autonomous_database.main.connection_urls[0].apex_url, "")
    medium = try(oci_database_autonomous_database.main.connection_urls[0].database_transforms_url, "")
    low    = try(oci_database_autonomous_database.main.connection_urls[0].graph_studio_url, "")
  }
  sensitive = true
}

output "service_console_url" {
  description = "Service console URL"
  value       = oci_database_autonomous_database.main.service_console_url
  sensitive   = true
}

output "nsg_id" {
  description = "OCID of the Network Security Group"
  value       = oci_core_network_security_group.atp.id
}

output "db_workload" {
  description = "Database workload type"
  value       = oci_database_autonomous_database.main.db_workload
}

output "is_free_tier" {
  description = "Whether database is using Always Free tier"
  value       = oci_database_autonomous_database.main.is_free_tier
}

output "lifecycle_state" {
  description = "Current lifecycle state"
  value       = oci_database_autonomous_database.main.state
}

# Helper output for connection configuration
output "connection_config" {
  description = "Connection configuration for applications"
  value = {
    host         = var.is_free_tier ? try(oci_database_autonomous_database.main.connection_strings[0].profiles[0].host_format, "") : oci_database_autonomous_database.main.private_endpoint
    port         = var.is_free_tier ? "1522" : "1521"
    service_high = "${var.db_name}_high"
    service_med  = "${var.db_name}_medium"
    service_low  = "${var.db_name}_low"
    protocol     = "tcps" # TLS
    require_mtls = var.require_mtls
  }
  sensitive = true
}

output "tns_aliases" {
  description = "TNS aliases for wallet-based connections (use these in connection strings)"
  value = {
    high   = "${var.db_name}_high"
    medium = "${var.db_name}_medium"
    low    = "${var.db_name}_low"
  }
}

output "wallet_download_instructions" {
  description = "Instructions for downloading ATP wallet (when mTLS is enabled)"
  value = var.require_mtls ? "Download wallet from OCI Console: Autonomous Databases > ${var.db_name} > DB Connection > Download Wallet" : "mTLS not required - wallet not needed"
}
