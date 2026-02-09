# OCI Bastion Module

Creates an OCI Bastion Service for secure access to private resources.

## Features

- Managed bastion service (no VM to maintain)
- Port forwarding sessions for private endpoints
- SSH sessions for instance access
- Configurable client CIDR allowlist
- Session TTL configuration
- Always Free eligible

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                                                              │
│  Internet                                                    │
│      │                                                       │
│      ▼                                                       │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  OCI Bastion Service                                  │   │
│  │  - Managed by Oracle                                  │   │
│  │  - No public VM required                              │   │
│  │  - Session-based access                               │   │
│  └─────────────────────┬────────────────────────────────┘   │
│                        │                                     │
│                        │ SSH Tunnel (Port Forwarding)        │
│                        ▼                                     │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Private Subnet (10.0.20.0/24)                        │   │
│  │                                                        │   │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────────┐  │   │
│  │  │ K8s API    │  │ Worker     │  │ ATP Private    │  │   │
│  │  │ (6443)     │  │ Nodes      │  │ Endpoint       │  │   │
│  │  └────────────┘  └────────────┘  └────────────────┘  │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Usage

```hcl
module "bastion" {
  source = "../../modules/oci-bastion"

  compartment_id   = var.compartment_id
  bastion_name     = "oke-prod-bastion"
  target_subnet_id = module.network.private_subnet_id

  # Allowed client CIDRs (your IP/network)
  allowed_cidrs = ["0.0.0.0/0"]  # Restrict in production!

  # Session configuration
  max_session_ttl = 10800  # 3 hours

  common_tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `compartment_id` | OCI Compartment OCID | `string` | - | Yes |
| `bastion_name` | Bastion service name | `string` | - | Yes |
| `target_subnet_id` | Subnet for bastion to access | `string` | - | Yes |
| `allowed_cidrs` | Client CIDRs allowed to connect | `list(string)` | `["0.0.0.0/0"]` | No |
| `max_session_ttl` | Max session TTL in seconds | `number` | `10800` | No |
| `common_tags` | Tags to apply | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| `bastion_id` | Bastion service OCID |
| `bastion_name` | Bastion service name |

## Creating Sessions

### Port Forwarding (for K8s API, databases)

```bash
# Create session
oci bastion session create-port-forwarding \
  --bastion-id $BASTION_ID \
  --display-name "k8s-api-session" \
  --ssh-public-key-file ~/.ssh/id_rsa.pub \
  --target-private-ip 10.0.20.5 \
  --target-port 6443 \
  --session-ttl 10800 \
  --wait-for-state SUCCEEDED

# Start SSH tunnel
ssh -i ~/.ssh/id_rsa -N -L 6443:10.0.20.5:6443 \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -p 22 <session-id>@host.bastion.<region>.oci.oraclecloud.com
```

### Automated Tunnel Script

Use the provided script for automatic tunnel management:

```bash
# Set environment variables
export BASTION_OCID="ocid1.bastion.oc1..."
export K8S_PRIVATE_ENDPOINT="10.0.20.5"

# Start tunnel (idempotent - reuses existing if valid)
./scripts/oci-bastion-kube-tunnel.sh

# Use generated kubeconfig
export KUBECONFIG=./kubeconfig.bastion
kubectl get nodes
```

### SSH Session (for instance access)

```bash
# Create managed SSH session
oci bastion session create-managed-ssh \
  --bastion-id $BASTION_ID \
  --display-name "worker-ssh" \
  --ssh-public-key-file ~/.ssh/id_rsa.pub \
  --target-resource-id <instance-ocid> \
  --target-os-username opc \
  --session-ttl 10800 \
  --wait-for-state SUCCEEDED
```

## Session Types

| Type | Use Case | Target |
|------|----------|--------|
| **Port Forwarding** | K8s API, databases, internal services | Private IP + port |
| **Managed SSH** | Instance shell access | Instance OCID |

## Security Best Practices

### Restrict Client CIDRs

```hcl
# Production: Restrict to known networks
allowed_cidrs = [
  "203.0.113.0/24",    # Office network
  "198.51.100.10/32",  # VPN exit IP
]
```

### Session TTL

```hcl
# Shorter sessions for higher security
max_session_ttl = 3600  # 1 hour
```

### Audit Sessions

```bash
# List active sessions
oci bastion session list --bastion-id $BASTION_ID --all

# Review session details
oci bastion session get --session-id <session-ocid>
```

## Cost

| Item | Cost |
|------|------|
| Bastion Service | **Free** |
| Sessions | **Free** |
| Data Transfer | Standard OCI rates |

## Troubleshooting

### Session Creation Fails

```bash
# Check bastion status
oci bastion bastion get --bastion-id $BASTION_ID

# Verify subnet has route to target
oci network route-table get --rt-id <route-table-ocid>
```

### SSH Connection Refused

```bash
# Verify session is ACTIVE
oci bastion session get --session-id $SESSION_ID \
  --query 'data."lifecycle-state"'

# Check SSH key matches
ssh-keygen -lf ~/.ssh/id_rsa.pub
```

### Tunnel Not Responding

```bash
# Kill existing tunnel
pkill -f "ssh.*bastion"

# Recreate session (sessions expire)
./scripts/oci-bastion-kube-tunnel.sh
```

## Notes

- Sessions expire after TTL - recreate as needed
- Bastion service is regional - create per region
- Port forwarding sessions support any TCP port
- Only one bastion service per subnet recommended
