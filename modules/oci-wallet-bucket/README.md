# OCI Wallet Bucket Module

Creates an Object Storage bucket for storing ATP wallet ZIP files.

## Features

- Private bucket (no public access)
- Versioning enabled for rotation history
- Lifecycle policy retains only last 3 versions
- Standard storage tier (free tier compatible)

## Usage

```hcl
module "wallet_bucket" {
  source = "../../../modules/oci-wallet-bucket"
  
  compartment_id = var.compartment_id
  bucket_name    = "oke-staging-atp-wallets"
  namespace      = var.tenancy_namespace
  
  common_tags = {
    Environment = "staging"
    Purpose     = "atp-wallet-storage"
  }
}
```

## Outputs

- `bucket_name` - Name of the created bucket
- `bucket_namespace` - Object Storage namespace
- `bucket_id` - Bucket OCID
