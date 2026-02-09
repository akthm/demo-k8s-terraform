# OKE Node Pool Module

Creates worker node pools for OKE clusters.

## Features

- Flexible compute shapes (E3.Flex, E4.Flex, A1.Flex)
- Configurable OCPU and memory per node
- OKE-optimized images (auto-selected by shape/arch)
- Boot volume sizing and encryption
- Placement configuration for single/multi-AD
- Cloud-init user data support

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Node Pool                                                   │
│                                                              │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐ │
│  │  Node 1        │  │  Node 2        │  │  Node 3        │ │
│  │  E4.Flex       │  │  E4.Flex       │  │  E4.Flex       │ │
│  │  4 OCPU        │  │  4 OCPU        │  │  4 OCPU        │ │
│  │  32 GB RAM     │  │  32 GB RAM     │  │  32 GB RAM     │ │
│  │                │  │                │  │                │ │
│  │  ┌──────────┐  │  │  ┌──────────┐  │  │  ┌──────────┐  │ │
│  │  │ kubelet  │  │  │  │ kubelet  │  │  │  │ kubelet  │  │ │
│  │  │ kube-prxy│  │  │  │ kube-prxy│  │  │  │ kube-prxy│  │ │
│  │  │ containrd│  │  │  │ containrd│  │  │  │ containrd│  │ │
│  │  └──────────┘  │  │  └──────────┘  │  │  └──────────┘  │ │
│  └────────────────┘  └────────────────┘  └────────────────┘ │
│                                                              │
│  Private Subnet: 10.0.20.0/24                               │
└─────────────────────────────────────────────────────────────┘
```

## Usage

```hcl
module "nodepool" {
  source = "../../modules/oke-nodepool"

  compartment_id     = var.compartment_id
  cluster_id         = module.cluster.cluster_id
  node_pool_name     = "oke-prod"
  kubernetes_version = "v1.29.1"

  # Worker node configuration
  worker_count     = 3
  worker_shape     = "VM.Standard.E4.Flex"
  worker_ocpus     = 4
  worker_memory_gb = 32

  # Boot volume
  worker_boot_volume_gb = 100

  # Placement
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  node_subnet_id      = module.network.private_subnet_id

  # Security
  enable_pv_encryption = true

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
| `cluster_id` | OKE Cluster OCID | `string` | - | Yes |
| `node_pool_name` | Node pool name | `string` | - | Yes |
| `kubernetes_version` | Kubernetes version (must match cluster) | `string` | - | Yes |
| `worker_count` | Number of worker nodes | `number` | `2` | No |
| `worker_shape` | Compute shape | `string` | `"VM.Standard.E4.Flex"` | No |
| `worker_ocpus` | OCPUs per node | `number` | `2` | No |
| `worker_memory_gb` | Memory (GB) per node | `number` | `16` | No |
| `worker_boot_volume_gb` | Boot volume size (GB) | `number` | `50` | No |
| `node_image_id` | Custom OKE image OCID (auto-detected if empty) | `string` | `""` | No |
| `availability_domain` | AD for node placement | `string` | - | Yes |
| `node_subnet_id` | Subnet for worker nodes | `string` | - | Yes |
| `enable_pv_encryption` | Enable PV transit encryption | `bool` | `true` | No |
| `common_tags` | Tags to apply | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| `node_pool_id` | Node Pool OCID |
| `node_pool_name` | Node Pool name |
| `worker_count` | Number of nodes |

## Compute Shapes

### Production Shapes

| Shape | Architecture | Use Case | Approx. Cost |
|-------|--------------|----------|--------------|
| `VM.Standard.E4.Flex` | x86 (AMD) | General purpose | ~$0.03/OCPU/hour |
| `VM.Standard.E3.Flex` | x86 (AMD) | General purpose | ~$0.03/OCPU/hour |
| `VM.Standard3.Flex` | x86 (Intel) | Intel workloads | ~$0.04/OCPU/hour |
| `VM.Standard.A1.Flex` | ARM (Ampere) | Cost-optimized | ~$0.01/OCPU/hour |

### Always Free Shapes

| Shape | Free Allocation | Notes |
|-------|-----------------|-------|
| `VM.Standard.A1.Flex` | 4 OCPU, 24 GB | ARM only |
| `VM.Standard.E2.1.Micro` | 2 instances | Limited resources |

## Recommended Configurations

### Production (Paid)

```hcl
worker_count     = 3
worker_shape     = "VM.Standard.E4.Flex"
worker_ocpus     = 4
worker_memory_gb = 32
```

**Monthly Cost**: ~$180 (3 nodes × 4 OCPU × 730 hours × $0.03/OCPU/hour)

### Development (Always Free)

```hcl
worker_count     = 2
worker_shape     = "VM.Standard.A1.Flex"
worker_ocpus     = 2
worker_memory_gb = 12
```

**Monthly Cost**: $0 (within Always Free limits)

## Image Selection

The module automatically selects the appropriate OKE-optimized image based on:

1. **Architecture**: x86 vs ARM based on shape
2. **GPU**: Excludes GPU images for non-GPU shapes
3. **OKE Optimized**: Prefers OKE-specific images

To use a specific image:

```hcl
node_image_id = "ocid1.image.oc1.il-jerusalem-1.xxx"
```

## Scaling

### Manual Scaling

```bash
# Scale via Terraform
terraform apply -var="worker_count=5"

# Scale via OCI CLI
oci ce node-pool update \
  --node-pool-id $NODEPOOL_ID \
  --size 5
```

### Cluster Autoscaler

For automatic scaling, deploy the Kubernetes Cluster Autoscaler with OCI provider.

## Notes

- Node pool Kubernetes version must match cluster version
- Jerusalem region has a single AD - all nodes in same AD
- OKE images are automatically updated by Oracle
- Nodes join cluster automatically after provisioning
