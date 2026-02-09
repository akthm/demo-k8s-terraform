# OCI Vault Module Variables

variable "compartment_id" {
  description = "OCID of the compartment where vault will be created"
  type        = string
}

variable "tenancy_ocid" {
  description = "OCID of the tenancy (required for dynamic group creation)"
  type        = string
}

variable "vault_name" {
  description = "Name of the vault"
  type        = string
}

variable "vault_type" {
  description = "Vault type: DEFAULT or VIRTUAL_PRIVATE"
  type        = string
  default     = "DEFAULT"
}

variable "cluster_name" {
  description = "Name of the OKE cluster (used for dynamic group naming)"
  type        = string
}

variable "cluster_id" {
  description = "OCID of the OKE cluster (used for dynamic group matching rule)"
  type        = string
  default     = ""
}

variable "create_dynamic_group" {
  description = "Whether to create a dynamic group for OKE nodes"
  type        = bool
  default     = true
}

variable "existing_dynamic_group_name" {
  description = "Name of existing dynamic group (if create_dynamic_group is false)"
  type        = string
  default     = ""
}

variable "create_iam_policy" {
  description = "Whether to create IAM policy for vault access"
  type        = bool
  default     = true
}

variable "application_secrets" {
  description = "Map of application secrets to create (one secret per application with JSON data)"
  type = map(object({
    description = string
    data        = map(string)
  }))
  default = {}
}

variable "tags" {
  description = "Freeform tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "wallet_bucket_name" {
  description = "Name of the Object Storage bucket containing ATP wallet"
  type        = string
  default     = ""
}

variable "wallet_object_name" {
  description = "Name of the wallet object in the bucket"
  type        = string
  default     = "stagingdb_wallet.zip"
}

variable "wallet_bucket_namespace" {
  description = "Object Storage namespace"
  type        = string
  default     = ""
}

variable "region" {
  description = "OCI region"
  type        = string
  default     = ""
}
