# OCI Vault Module
# Creates OCI Vault, master encryption key, and IAM policies for OKE access

terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
  }
}

# OCI Vault
resource "oci_kms_vault" "main" {
  compartment_id = var.compartment_id
  display_name   = var.vault_name
  vault_type     = var.vault_type

  freeform_tags = var.tags
}

# Master Encryption Key
resource "oci_kms_key" "main" {
  compartment_id = var.compartment_id
  display_name   = "${var.vault_name}-master-key"
  
  key_shape {
    algorithm = "AES"
    length    = 32
  }

  management_endpoint = oci_kms_vault.main.management_endpoint
  
  protection_mode = "SOFTWARE"

  freeform_tags = var.tags
}

# Dynamic Group for OKE nodes to access vault
resource "oci_identity_dynamic_group" "oke_nodes" {
  count = var.create_dynamic_group ? 1 : 0

  compartment_id = var.tenancy_ocid
  name           = "${var.cluster_name}-vault-access"
  description    = "Dynamic group for OKE ${var.cluster_name} nodes to access vault"
  
  # Match all instances in the compartment
  # Note: OKE worker nodes don't always have the oke-cluster-id freeform tag automatically applied
  # Using compartment-only matching for simplicity and reliability
  matching_rule = "ANY {instance.compartment.id = '${var.compartment_id}'}"

  freeform_tags = var.tags
}

# IAM Policy for vault access
resource "oci_identity_policy" "vault_access" {
  count = var.create_iam_policy ? 1 : 0

  compartment_id = var.compartment_id
  name           = "${var.cluster_name}-vault-read-policy"
  description    = "Allow OKE nodes to read secrets from vault and access ATP wallet bucket"

  statements = concat(
    [
      "Allow dynamic-group ${var.create_dynamic_group ? oci_identity_dynamic_group.oke_nodes[0].name : var.existing_dynamic_group_name} to read secret-family in compartment id ${var.compartment_id}",
      "Allow dynamic-group ${var.create_dynamic_group ? oci_identity_dynamic_group.oke_nodes[0].name : var.existing_dynamic_group_name} to read vaults in compartment id ${var.compartment_id}",
      "Allow dynamic-group ${var.create_dynamic_group ? oci_identity_dynamic_group.oke_nodes[0].name : var.existing_dynamic_group_name} to use keys in compartment id ${var.compartment_id}"
    ],
    var.wallet_bucket_name != "" ? [
      "Allow dynamic-group ${var.create_dynamic_group ? oci_identity_dynamic_group.oke_nodes[0].name : var.existing_dynamic_group_name} to read buckets in compartment id ${var.compartment_id} where target.bucket.name = '${var.wallet_bucket_name}'",
      "Allow dynamic-group ${var.create_dynamic_group ? oci_identity_dynamic_group.oke_nodes[0].name : var.existing_dynamic_group_name} to read objects in compartment id ${var.compartment_id} where target.bucket.name = '${var.wallet_bucket_name}'"
    ] : []
  )

  freeform_tags = var.tags
}

# Application Secrets (JSON format, one per application)
resource "oci_vault_secret" "application_secrets" {
  for_each = var.application_secrets

  compartment_id = var.compartment_id
  vault_id       = oci_kms_vault.main.id
  key_id         = oci_kms_key.main.id
  secret_name    = each.key
  description    = each.value.description

  secret_content {
    content_type = "BASE64"
    content      = base64encode(jsonencode(each.value.data))
  }

  freeform_tags = var.tags
}

# ATP Wallet Bucket Information Secret
resource "oci_vault_secret" "adb_wallet_bucket_info" {
  count = var.wallet_bucket_name != "" ? 1 : 0

  compartment_id = var.compartment_id
  vault_id       = oci_kms_vault.main.id
  key_id         = oci_kms_key.main.id
  secret_name    = "adb-wallet-bucket-info"
  description    = "Object Storage bucket details for ATP wallet"
  
  secret_content {
    content_type = "BASE64"
    content = base64encode(jsonencode({
      bucket_name  = var.wallet_bucket_name
      object_name  = var.wallet_object_name
      namespace    = var.wallet_bucket_namespace
      region       = var.region
    }))
  }
  
  freeform_tags = var.tags
}
