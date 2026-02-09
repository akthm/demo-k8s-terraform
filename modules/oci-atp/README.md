# OCI Autonomous Database (ATP) Module

Terraform module for creating OCI Autonomous Transaction Processing (ATP) database with TLS-only private endpoint. No wallet required for connectivity.

## Features

- Always Free tier eligible (1 OCPU, 20GB storage)
- Private endpoint in worker subnet (no public access)
- TLS-only connectivity (no mTLS wallet required)
- Network Security Group for controlled access
- PostgreSQL wire protocol compatible
- Auto-scaling support (paid tier only)

## Usage

```hcl
module "atp" {
  source = "../../modules/oci-atp"

  compartment_id       = var.compartment_id
  vcn_id               = module.network.vcn_id
  private_subnet_id    = module.network.private_subnet_id
  worker_subnet_cidr   = "10.0.20.0/24"
  
  db_name         = "stagingdb"
  display_name    = "OKE Staging Database"
  admin_password  = var.atp_admin_password # Store in Vault
  
  db_workload     = "OLTP"
  is_free_tier    = true
  require_mtls    = false  # TLS without wallet
  
  database_users = [
    {
      username = "flask_user"
      password = var.flask_db_password
    },
    {
      username = "keycloak"
      password = var.keycloak_db_password
    }
  ]

  tags = {
    Environment = "staging"
    ManagedBy   = "terraform"
  }
}
```

## Connectivity Without Wallet

With `require_mtls = false`, applications can connect using standard TLS:

### Python (psycopg2)
```python
import psycopg2

conn = psycopg2.connect(
    host="<private-endpoint>",
    port=1521,
    database="stagingdb_high",
    user="flask_user",
    password="<password>",
    sslmode="require"  # TLS without client cert
)
```

### Connection String
```
postgresql://flask_user:<password>@<private-endpoint>:1521/stagingdb_high?sslmode=require
```

### Java (JDBC)
```java
jdbc:oracle:thin:@tcps://<private-endpoint>:1522/stagingdb_high?TNS_ADMIN=/path/to/empty/dir
```

## Network Configuration

ATP is deployed in the **same private subnet as OKE workers** (10.0.20.0/24) with a dedicated Network Security Group:

- **Ingress**: TCP 1521-1522 from worker subnet CIDR
- **Egress**: TCP to worker subnet (responses)

No additional route tables or security list modifications required.

## Database User Creation

The module outputs a placeholder for database users. Actual user creation requires SQL execution:

```sql
-- Connect as ADMIN user
CREATE USER flask_user IDENTIFIED BY "SecurePassword123!";
GRANT CONNECT, RESOURCE TO flask_user;
ALTER USER flask_user QUOTA UNLIMITED ON DATA;

CREATE USER keycloak IDENTIFIED BY "KeycloakPass123!";
GRANT CONNECT, RESOURCE TO keycloak;
ALTER USER keycloak QUOTA UNLIMITED ON DATA;
```

Execute via:
- OCI Cloud Shell with SQL*Plus
- Bastion + SQL client
- OCI Database Tools (SQL Worksheet)
- Terraform null_resource with oci-cli

## Always Free Tier Limits

- **OCPUs**: 1 (fixed)
- **Storage**: 20 GB (fixed)
- **Concurrent connections**: 20
- **No auto-scaling**: Feature disabled for Always Free
- **Backup retention**: 60 days
- **Region availability**: Limited to home region
- **No private endpoints**: Must use public endpoint with IP whitelisting

> **Note**: For Always Free ATP with public endpoints, see archived documentation at [archive/atp-free-tier-docs/](../../archive/atp-free-tier-docs/)

## Production (Paid) Configuration

For production workloads, use paid tier with private endpoints and Data Guard:

```hcl
module "atp" {
  source = "../../modules/oci-atp"

  compartment_id       = var.compartment_id
  vcn_id               = module.network.vcn_id
  private_subnet_id    = module.network.private_subnet_id
  worker_subnet_cidr   = "10.0.20.0/24"
  
  db_name         = "proddb"
  display_name    = "Production Database"
  admin_password  = var.atp_admin_password
  
  # Production settings
  is_free_tier              = false
  cpu_core_count            = 2
  data_storage_size_in_tbs  = 1
  is_auto_scaling_enabled   = true
  
  # Private endpoint (paid tier only)
  use_private_endpoint = true
  
  # Autonomous Data Guard for DR
  is_local_data_guard_enabled = true
  
  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

### Production Features

| Feature | Free Tier | Paid Tier |
|---------|-----------|-----------|
| Private Endpoint | ❌ | ✅ |
| Auto-scaling (CPU) | ❌ | ✅ |
| Auto-scaling (Storage) | ❌ | ✅ |
| Data Guard | ❌ | ✅ |
| CPU | 1 OCPU | 1-128 OCPU |
| Storage | 20 GB | 1-128 TB |
| Connections | 20 | Unlimited |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| compartment_id | OCID of compartment | string | - | yes |
| vcn_id | OCID of VCN | string | - | yes |
| private_subnet_id | OCID of private subnet | string | - | yes |
| worker_subnet_cidr | Worker subnet CIDR | string | - | yes |
| db_name | Database name (max 14 chars) | string | - | yes |
| admin_password | ADMIN password | string | - | yes |
| is_free_tier | Use Always Free tier | bool | true | no |
| require_mtls | Require wallet-based mTLS | bool | false | no |
| db_workload | Workload type (OLTP/DW) | string | OLTP | no |

## Outputs

| Name | Description |
|------|-------------|
| atp_id | OCID of the database |
| private_endpoint | Private endpoint hostname |
| private_endpoint_ip | Private endpoint IP |
| connection_strings | Full connection strings |
| connection_config | Connection configuration object |
| nsg_id | Network Security Group OCID |

## Security Considerations

- **No public access**: Private endpoint only
- **TLS encryption**: In-transit encryption without wallet
- **NSG-based firewall**: Restrict to worker subnet only
- **Admin password**: Store in OCI Vault, rotate regularly
- **Application passwords**: Store in OCI Vault, access via External Secrets Operator
- **Always Free monitoring**: Use OCI monitoring to track usage limits
