# OCI Vault Module

Terraform module for creating OCI Vault with master encryption key, dynamic group for OKE instance principal authentication, and IAM policies for secure secret access.

## Features

- Creates OCI Vault (DEFAULT or VIRTUAL_PRIVATE type)
- Creates master AES-256 encryption key
- Creates dynamic group for OKE nodes to use instance principal authentication
- Creates IAM policy allowing read access to secrets
- Supports multiple application secrets (JSON format, one secret per application)

## Usage

```hcl
module "vault" {
  source = "../../modules/oci-vault"

  compartment_id = var.compartment_id
  tenancy_ocid   = var.tenancy_ocid
  vault_name     = "oke-staging-vault"
  cluster_name   = "oke-staging"

  application_secrets = {
    "flask-app" = {
      description = "Flask application secrets"
      data = {
        SECRET_KEY                = "your-secret-key"
        API_TEST_KEY             = "test-key"
        DB_USER                  = "flask_user"
        DB_PASSWORD              = "secure-password"
        DB_HOST                  = "atp-host.oraclecloud.com"
        DB_PORT                  = "1521"
        DB_NAME                  = "stagingdb_high"
        DATABASE_ENCRYPTION_KEY_V1 = "fernet-key"
        CURRENT_KEY_VERSION      = "v1"
      }
    }
    "keycloak" = {
      description = "Keycloak secrets"
      data = {
        admin-user     = "admin"
        admin-password = "admin-password"
        DB_USER        = "keycloak"
        DB_PASSWORD    = "keycloak-password"
        DB_HOST        = "atp-host.oraclecloud.com"
        DB_PORT        = "1521"
        DB_NAME        = "stagingdb_high"
      }
    }
    "cloudflare" = {
      description = "Cloudflare API token for DNS01 challenge"
      data = {
        CLOUDFLARE_API_TOKEN = "your-cloudflare-token"
      }
    }
  }

  tags = {
    Environment = "staging"
    ManagedBy   = "terraform"
  }
}
```

## Authentication

This module creates a dynamic group and IAM policy to enable OKE pods to access vault secrets using **instance principal authentication**. No API keys or credentials need to be stored in Kubernetes.

### How Instance Principal Works

1. OKE worker nodes are automatically members of the dynamic group
2. Dynamic group matches: `instance.compartment.id = '<compartment-ocid>'`
3. IAM policy grants: `Allow dynamic-group <name> to read secret-family`
4. External Secrets Operator uses `useInstancePrincipal: true` in ClusterSecretStore

## External Secrets Operator Integration

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: oci-vault
spec:
  provider:
    oracle:
      vault: <vault-ocid>
      region: il-jerusalem-1
      auth:
        useInstancePrincipal: true
```

## Always Free Tier

- Vault: First 20 secret versions free per month
- Additional secret versions: $0.03 per version per month
- Keys: Always free
- Dynamic groups and policies: Always free

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| compartment_id | OCID of the compartment | string | - | yes |
| tenancy_ocid | OCID of the tenancy | string | - | yes |
| vault_name | Name of the vault | string | - | yes |
| cluster_name | OKE cluster name | string | - | yes |
| vault_type | Vault type (DEFAULT or VIRTUAL_PRIVATE) | string | DEFAULT | no |
| application_secrets | Map of application secrets | map(object) | {} | no |
| create_dynamic_group | Create dynamic group | bool | true | no |
| create_iam_policy | Create IAM policy | bool | true | no |
| tags | Freeform tags | map(string) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| vault_id | OCID of the vault |
| vault_crypto_endpoint | Crypto endpoint URL |
| vault_management_endpoint | Management endpoint URL |
| key_id | OCID of master encryption key |
| dynamic_group_id | OCID of dynamic group |
| secret_ids | Map of secret names to OCIDs |
| region | Region where vault is deployed |
