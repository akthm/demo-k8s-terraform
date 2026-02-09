# OCI Vault Module Outputs

output "vault_id" {
  description = "OCID of the vault"
  value       = oci_kms_vault.main.id
}

output "vault_crypto_endpoint" {
  description = "Crypto endpoint of the vault"
  value       = oci_kms_vault.main.crypto_endpoint
}

output "vault_management_endpoint" {
  description = "Management endpoint of the vault"
  value       = oci_kms_vault.main.management_endpoint
}

output "key_id" {
  description = "OCID of the master encryption key"
  value       = oci_kms_key.main.id
}

output "dynamic_group_id" {
  description = "OCID of the dynamic group (if created)"
  value       = var.create_dynamic_group ? oci_identity_dynamic_group.oke_nodes[0].id : null
}

output "dynamic_group_name" {
  description = "Name of the dynamic group (if created)"
  value       = var.create_dynamic_group ? oci_identity_dynamic_group.oke_nodes[0].name : var.existing_dynamic_group_name
}

output "policy_id" {
  description = "OCID of the IAM policy (if created)"
  value       = var.create_iam_policy ? oci_identity_policy.vault_access[0].id : null
}

output "secret_ids" {
  description = "Map of application secret names to their OCIDs"
  value       = { for k, v in oci_vault_secret.application_secrets : k => v.id }
}

output "region" {
  description = "Region where vault is deployed"
  value       = oci_kms_vault.main.id != "" ? split(".", oci_kms_vault.main.id)[3] : ""
}

output "adb_wallet_bucket_info_secret_id" {
  description = "OCID of the ATP wallet bucket info secret"
  value       = var.wallet_bucket_name != "" ? oci_vault_secret.adb_wallet_bucket_info[0].id : null
}
