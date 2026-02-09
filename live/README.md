# Terragrunt Live Configuration

This directory contains Terragrunt configurations for deploying infrastructure across different environments.

## Directory Structure

```
live/
├── oci-staging/                  # OCI Production/Staging environment
│   ├── terragrunt.hcl           # Environment-level configuration
│   ├── env.hcl                  # OCI-specific variables
│   ├── backend.tf               # S3 remote state configuration
│   ├── network/                 # VCN, subnets, gateways
│   ├── cluster/                 # OKE control plane
│   ├── nodepool/                # Worker node pool
│   ├── bastion/                 # Bastion service for K8s API access
│   ├── vault/                   # OCI Vault + secrets
│   ├── atp/                     # Autonomous Transaction Processing DB
│   ├── wallet-bucket/           # ATP wallet storage
│   ├── edge-proxy/              # NGINX edge proxy VM
│   ├── load-balancer/           # OCI Network Load Balancer
│   └── cluster-services/        # ArgoCD, ESO, cert-manager, NGINX
│
└── local-dev/                    # Local development environment
    ├── terragrunt.hcl           # Environment-level configuration
    ├── env.hcl                  # Environment-specific variables
    ├── kind/                    # KIND cluster module
    ├── metallb/                 # MetalLB for LoadBalancer support
    └── cluster-services/        # Cluster services (ArgoCD, etc.)
```

## Environments

### OCI Staging (Production)

Full OCI infrastructure for production workloads:

| Module | Description | Dependencies |
|--------|-------------|--------------|
| `network` | VCN, subnets, Internet/NAT/Service gateways | None |
| `cluster` | OKE Kubernetes control plane | network |
| `nodepool` | Worker node pool (E3/E4.Flex) | cluster |
| `bastion` | Bastion service for private K8s API | network |
| `vault` | OCI Vault, master key, app secrets | nodepool |
| `atp` | Autonomous Database | network, vault |
| `wallet-bucket` | Object Storage for ATP wallet | vault |
| `edge-proxy` | NGINX reverse proxy VM | network |
| `load-balancer` | Network Load Balancer | edge-proxy |
| `cluster-services` | ArgoCD, ESO, NGINX Ingress | nodepool, vault |

### Local Development

Lightweight local environment using Kind:

| Module | Description | Dependencies |
|--------|-------------|--------------|
| `kind` | Kind Kubernetes cluster | None |
| `metallb` | MetalLB LoadBalancer | kind |
| `cluster-services` | ArgoCD, NGINX Ingress | kind, metallb |

## Usage

### OCI Staging Deployment

Deploy OCI infrastructure in dependency order:

```bash
# Set OCI environment variables
export TF_VAR_compartment_id="ocid1.compartment.oc1..xxx"
export TF_VAR_tenancy_id="ocid1.tenancy.oc1..xxx"

# Deploy all modules (recommended for fresh deployment)
cd live/oci-staging
terragrunt run-all apply

# Or deploy individually in order
cd live/oci-staging/network && terragrunt apply
cd ../cluster && terragrunt apply
cd ../nodepool && terragrunt apply
cd ../bastion && terragrunt apply
cd ../vault && terragrunt apply
cd ../atp && terragrunt apply
cd ../cluster-services && terragrunt apply
```

### Access OKE Cluster (Private Endpoint)

```bash
# Set bastion environment variables
export BASTION_OCID=$(cd live/oci-staging/bastion && terragrunt output -raw bastion_id)
export K8S_PRIVATE_ENDPOINT=$(cd live/oci-staging/cluster && terragrunt output -raw private_endpoint)
export CLUSTER_ID=$(cd live/oci-staging/cluster && terragrunt output -raw cluster_id)

# Start bastion tunnel
./scripts/oci-bastion-kube-tunnel.sh

# Use the generated kubeconfig
export KUBECONFIG=./kubeconfig.bastion
kubectl get nodes
```

### Local Development Deployment

Deploy local Kind cluster:

```bash
cd live/local-dev
terragrunt run-all apply
```

### Deploy Individual Module

Deploy just the KIND cluster:

```bash
cd live/local-dev/kind
terragrunt apply
```

Deploy just the cluster services:

```bash
cd live/local-dev/cluster-services
terragrunt apply
```

### Destroy Everything

Destroy all resources in reverse dependency order:

```bash
# OCI Staging
cd live/oci-staging
terragrunt run-all destroy

# Local Dev
cd live/local-dev
terragrunt run-all destroy
```

### Validate Configuration

```bash
cd live/oci-staging
terragrunt run-all validate
```

### Plan All Changes

```bash
cd live/oci-staging
terragrunt run-all plan
```

## Environment Variables

### OCI Staging

```bash
# Required
export TF_VAR_compartment_id="ocid1.compartment.oc1..xxx"
export TF_VAR_tenancy_id="ocid1.tenancy.oc1..xxx"
export OCI_CLI_PROFILE="DEFAULT"

# Optional (for cluster-services)
export TF_VAR_git_token="ghp_xxx"  # GitHub token for ArgoCD
```

### Local Development

```bash
# GitHub/GitLab token for ArgoCD private repo access
export TF_VAR_git_token="your-github-token"
```

## Dependencies

The modules are configured with proper dependencies:

1. **kind** - Creates the local Kubernetes cluster (no dependencies)
2. **cluster-services** - Deploys services to the cluster (depends on kind)

Terragrunt automatically handles dependency ordering during `run-all` operations.

## State Management

For local development, Terraform state is stored locally in each module directory under `.terraform/`.

For production environments, configure remote state in the root `terragrunt.hcl`.

## Troubleshooting

### Clear Terragrunt Cache

```bash
cd live/local-dev
find . -type d -name ".terragrunt-cache" -exec rm -rf {} + 2>/dev/null
```

### Reinitialize Terraform

```bash
cd live/local-dev/kind  # or cluster-services
rm -rf .terraform .terraform.lock.hcl
terragrunt init
```

### Check Dependency Graph

```bash
cd live/local-dev
terragrunt graph-dependencies
```
