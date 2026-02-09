# OKE Cluster Module

Creates an Oracle Kubernetes Engine (OKE) control plane.

## Features

- OKE managed Kubernetes control plane
- Support for BASIC_CLUSTER (free) or ENHANCED_CLUSTER (paid)
- Flannel or OCI VCN-Native CNI options
- Private or public API endpoint
- Configurable Kubernetes version
- Automatic kubeconfig generation

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  OKE Cluster (Managed Control Plane)                        │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  API Server                                             │ │
│  │  - Private endpoint (recommended)                       │ │
│  │  - Access via Bastion tunnel                           │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  etcd (managed)                                         │ │
│  │  - Encrypted at rest                                    │ │
│  │  - Automatic backups                                    │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Control Plane Components                               │ │
│  │  - Scheduler                                            │ │
│  │  - Controller Manager                                   │ │
│  │  - Cloud Controller                                     │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Usage

```hcl
module "cluster" {
  source = "../../modules/oke-cluster"

  compartment_id     = var.compartment_id
  cluster_name       = "oke-prod"
  kubernetes_version = "v1.29.1"
  vcn_id             = module.network.vcn_id

  # Cluster type
  cluster_type = "ENHANCED_CLUSTER"  # or "BASIC_CLUSTER" for free tier

  # CNI configuration
  cni_type = "FLANNEL_OVERLAY"  # or "OCI_VCN_IP_NATIVE"

  # Endpoint configuration
  endpoint_public    = false  # Private endpoint (recommended)
  endpoint_subnet_id = module.network.private_subnet_id

  # Network configuration
  pods_cidr     = "10.244.0.0/16"
  services_cidr = "10.96.0.0/16"

  # Load balancer subnet
  service_lb_subnet_ids = [module.network.public_subnet_id]

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
| `cluster_name` | Cluster name | `string` | - | Yes |
| `kubernetes_version` | Kubernetes version | `string` | `"v1.29.1"` | No |
| `vcn_id` | VCN OCID | `string` | - | Yes |
| `cluster_type` | BASIC_CLUSTER or ENHANCED_CLUSTER | `string` | `"BASIC_CLUSTER"` | No |
| `cni_type` | FLANNEL_OVERLAY or OCI_VCN_IP_NATIVE | `string` | `"FLANNEL_OVERLAY"` | No |
| `endpoint_public` | Enable public K8s API endpoint | `bool` | `false` | No |
| `endpoint_subnet_id` | Subnet for K8s API endpoint | `string` | - | Yes |
| `pods_cidr` | Pod network CIDR | `string` | `"10.244.0.0/16"` | No |
| `services_cidr` | Service network CIDR | `string` | `"10.96.0.0/16"` | No |
| `service_lb_subnet_ids` | Subnets for service load balancers | `list(string)` | - | Yes |
| `enable_dashboard` | Enable K8s dashboard | `bool` | `false` | No |
| `common_tags` | Tags to apply | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| `cluster_id` | OKE Cluster OCID |
| `cluster_name` | Cluster name |
| `kubernetes_version` | Kubernetes version |
| `private_endpoint` | Private API endpoint IP |
| `public_endpoint` | Public API endpoint (if enabled) |
| `kubeconfig` | Raw kubeconfig content |

## Cluster Types

| Type | Features | Cost |
|------|----------|------|
| **BASIC_CLUSTER** | Standard K8s, no SLA | Free |
| **ENHANCED_CLUSTER** | SLA, virtual nodes, workload identity | ~$75/month |

### Production Recommendation

For production workloads, use `ENHANCED_CLUSTER` for:
- 99.95% SLA guarantee
- Virtual node support
- Workload identity (OCI IAM for pods)
- Advanced networking features

## CNI Options

| CNI | Description | Use Case |
|-----|-------------|----------|
| **FLANNEL_OVERLAY** | Overlay network, pods get virtual IPs | General purpose, simpler |
| **OCI_VCN_IP_NATIVE** | Pods get VCN IPs directly | Network policies, direct pod routing |

## Accessing Private Clusters

For clusters with `endpoint_public = false`:

```bash
# Use bastion tunnel
./scripts/oci-bastion-kube-tunnel.sh

# Export generated kubeconfig
export KUBECONFIG=./kubeconfig.bastion

# Verify access
kubectl get nodes
```

## Notes

- Kubernetes version must match node pool version
- Private endpoints are more secure but require bastion access
- Control plane is fully managed by Oracle
- etcd backups are automatic and managed
