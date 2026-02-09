# OCI Network Module

Creates the VCN (Virtual Cloud Network) and associated networking components for OKE clusters.

## Features

- VCN with configurable CIDR block
- Internet Gateway (Always Free)
- NAT Gateway (optional, paid ~$33/month)
- Service Gateway for OCI services access
- Public and private subnets
- Security lists with OKE-required rules
- Route tables for public/private traffic

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  VCN (10.0.0.0/16)                                          │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Internet Gateway                                       │ │
│  └─────────────────────┬──────────────────────────────────┘ │
│                        │                                     │
│  ┌─────────────────────▼────────────────────────────────┐   │
│  │  Public Subnet (10.0.10.0/24)                         │   │
│  │  - Load Balancers                                     │   │
│  │  - Bastion (if public)                                │   │
│  │  - Edge Proxy VM                                      │   │
│  └─────────────────────┬────────────────────────────────┘   │
│                        │                                     │
│  ┌─────────────────────▼────────────────────────────────┐   │
│  │  Private Subnet (10.0.20.0/24)                        │   │
│  │  - OKE Worker Nodes                                   │   │
│  │  - ATP Private Endpoint                               │   │
│  │  - Internal Services                                  │   │
│  └──────────────────────────────────────────────────────┘   │
│                        │                                     │
│  ┌─────────────────────▼────────────────────────────────┐   │
│  │  NAT Gateway (optional)    Service Gateway            │   │
│  │  - Outbound internet       - OCI services access      │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Usage

```hcl
module "network" {
  source = "../../modules/oci-network"

  compartment_id = var.compartment_id
  cluster_name   = "oke-prod"
  vcn_cidr       = "10.0.0.0/16"

  # Subnet CIDRs
  public_subnet_cidr  = "10.0.10.0/24"
  private_subnet_cidr = "10.0.20.0/24"

  # Gateway options
  enable_nat_gateway     = true   # Required for private subnet internet access
  enable_service_gateway = true   # Recommended for OCI services

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
| `cluster_name` | Name prefix for resources | `string` | - | Yes |
| `vcn_cidr` | VCN CIDR block | `string` | `"10.0.0.0/16"` | No |
| `public_subnet_cidr` | Public subnet CIDR | `string` | `"10.0.10.0/24"` | No |
| `private_subnet_cidr` | Private subnet CIDR | `string` | `"10.0.20.0/24"` | No |
| `enable_nat_gateway` | Create NAT Gateway (paid) | `bool` | `false` | No |
| `enable_service_gateway` | Create Service Gateway | `bool` | `true` | No |
| `common_tags` | Tags to apply to resources | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| `vcn_id` | VCN OCID |
| `public_subnet_id` | Public subnet OCID |
| `private_subnet_id` | Private subnet OCID |
| `nat_gateway_id` | NAT Gateway OCID (if created) |
| `internet_gateway_id` | Internet Gateway OCID |

## Security Lists

### Public Subnet Rules

| Direction | Protocol | Port | Source/Dest | Purpose |
|-----------|----------|------|-------------|---------|
| Ingress | TCP | 443 | 0.0.0.0/0 | HTTPS traffic |
| Ingress | TCP | 80 | 0.0.0.0/0 | HTTP traffic |
| Ingress | TCP | 22 | Your IP | SSH (bastion) |
| Egress | All | All | 0.0.0.0/0 | Outbound traffic |

### Private Subnet Rules

| Direction | Protocol | Port | Source/Dest | Purpose |
|-----------|----------|------|-------------|---------|
| Ingress | TCP | All | 10.0.10.0/24 | From public subnet |
| Ingress | TCP | 10250 | 10.0.20.0/24 | Kubelet |
| Ingress | TCP | 6443 | 10.0.10.0/24 | K8s API (from bastion) |
| Egress | All | All | 0.0.0.0/0 | Outbound traffic |

## Cost Considerations

| Resource | Always Free | Paid Cost |
|----------|-------------|-----------|
| VCN | ✅ Yes | - |
| Internet Gateway | ✅ Yes | - |
| Subnets | ✅ Yes | - |
| Route Tables | ✅ Yes | - |
| Security Lists | ✅ Yes | - |
| NAT Gateway | ❌ No | ~$33/month |
| Service Gateway | ✅ Yes | - |

## Notes

- For Always Free, disable NAT Gateway and use public subnets or Service Gateway for egress
- Jerusalem region (il-jerusalem-1) has a single Availability Domain
- Security lists are stateful by default
