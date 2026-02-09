# OCI Staging Environment - README
# OCI Always Free Tier Kubernetes Cluster

## Overview

This environment deploys a fully functional Kubernetes cluster on OCI using the **Always Free** tier resources in the **il-jerusalem-1** region.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        VCN (10.0.0.0/16)                        │
│                                                                 │
│  ┌─────────────────────────┐  ┌──────────────────────────────┐  │
│  │   Public Subnet         │  │   Private Subnet             │  │
│  │   10.0.10.0/24          │  │   10.0.20.0/24               │  │
│  │                         │  │                              │  │
│  │  ┌──────────────────┐   │  │  ┌────────────────────────┐  │  │
│  │  │ Edge Proxy       │───┼──┼─▶│  OKE Worker Nodes     │  │  │
│  │  │ E2.1.Micro       │   │  │  │  2x A1.Flex           │  │  │
│  │  │ (NGINX)          │   │  │  │  (2 OCPU/12GB each)   │  │  │
│  │  └──────────────────┘   │  │  └────────────────────────┘  │  │
│  │         ▲               │  │            ▲                 │  │
│  └─────────┼───────────────┘  └────────────┼─────────────────┘  │
│            │                               │                    │
│      Internet Gateway              OCI Bastion (managed)        │
└────────────┼───────────────────────────────┼────────────────────┘
             │                               │
        HTTP/HTTPS                      SSH Sessions
        from Internet                   (time-bound)
```

## Always Free Resources Used

| Resource | Spec | Free Tier Limit | This Env |
|----------|------|-----------------|----------|
| A1 Flex Compute | OCPU | 4 OCPUs total | 4 (2×2) |
| A1 Flex Memory | GB | 24 GB total | 24 (2×12) |
| Block Volume | GB | 200 GB total | 100 (2×50) |
| E2.1.Micro | Instances | 2 | 1 (edge proxy) |
| Bastion | Service | 5 per region | 1 |
| OKE Control Plane | Cluster | Unlimited (BASIC) | 1 |

## Deployment Order

```bash
# 1. Network infrastructure
cd network && terragrunt apply

# 2. Bastion for SSH access
cd ../bastion && terragrunt apply

# 3. OKE cluster control plane
cd ../cluster && terragrunt apply

# 4. Worker node pool
cd ../nodepool && terragrunt apply

# 5. Fetch kubeconfig
cd ../cluster && terragrunt output -raw kubeconfig > ~/.kube/oci-staging.yaml
export KUBECONFIG=~/.kube/oci-staging.yaml

# 6. Cluster add-ons (storage class, etc.)
cd ../addons && terragrunt apply

# 7. Cluster services (ArgoCD, Ingress Controller)
cd ../cluster-services && terragrunt apply

# 8. Edge proxy (optional but recommended)
cd ../edge-proxy && terragrunt apply

# 9. Point DNS to edge proxy public IP
```

## Required Environment Variables

```bash
# OCI Authentication
export TG_VAR_oci_tenancy_ocid="ocid1.tenancy.oc1..xxx"
export TG_VAR_oci_compartment_id="ocid1.compartment.oc1..xxx"
export TG_VAR_oci_user_ocid="ocid1.user.oc1..xxx"
export TG_VAR_oci_fingerprint="xx:xx:xx:xx..."
export TG_VAR_oci_private_key_path="~/.oci/oci_api_key.pem"

# SSH access
export TG_VAR_ssh_public_key="ssh-rsa AAAA..."

# Bastion access (your IP)
export TG_VAR_bastion_allowed_cidrs="1.2.3.4/32,5.6.7.8/32"

# GitOps (for ArgoCD)
export TG_VAR_git_token="ghp_xxx"
```

## Cost Safety Checklist

- [x] OKE cluster type = BASIC_CLUSTER (no control plane fee)
- [x] NAT Gateway disabled (billable)
- [x] No paid Load Balancer (using edge proxy instead)
- [x] Total storage ≤ 200 GB
- [x] Total A1 OCPUs ≤ 4
- [x] Total A1 memory ≤ 24 GB
- [x] Single AD configuration (Jerusalem has 1 AD)
