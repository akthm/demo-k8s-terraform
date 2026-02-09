# OCI OKE Infrastructure with GitOps

Production-ready Oracle Cloud Infrastructure (OCI) Kubernetes Engine (OKE) cluster deployed via Terraform/Terragrunt with GitOps capabilities.

## 📋 Overview

This infrastructure provides a complete Kubernetes platform on OCI with enterprise-grade security, secrets management, and database services.

| Component | Description | OCI Service |
|-----------|-------------|-------------|
| **Networking** | VCN with public/private subnets, gateways | VCN, NAT Gateway, Service Gateway |
| **Kubernetes** | Managed Kubernetes control plane | OKE (Oracle Kubernetes Engine) |
| **Compute** | Worker node pool with autoscaling | Compute (E3/E4.Flex shapes) |
| **Database** | Autonomous Transaction Processing | ATP with Data Guard |
| **Secrets** | Centralized secrets management | OCI Vault + ESO |
| **Access** | Secure private endpoint access | Bastion Service |
| **Ingress** | Load balancing and traffic routing | Network Load Balancer |
| **GitOps** | Continuous deployment from Git | ArgoCD (self-managed) |

## 🏗️ Architecture

```
┌────────────────────────────────────────────────────────────────────────────┐
│                        OCI Region (il-jerusalem-1)                          │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  VCN (10.0.0.0/16)                                                   │   │
│  │                                                                      │   │
│  │  ┌──────────────────────┐    ┌──────────────────────┐              │   │
│  │  │  Public Subnet       │    │  Private Subnet       │              │   │
│  │  │  10.0.10.0/24       │    │  10.0.20.0/24        │              │   │
│  │  │                      │    │                       │              │   │
│  │  │  ┌────────────────┐ │    │  ┌─────────────────┐ │              │   │
│  │  │  │ Network LB     │ │    │  │ OKE Worker Nodes│ │              │   │
│  │  │  │ (443, 80)      │─┼────┼─►│ (2+ nodes)      │ │              │   │
│  │  │  └────────────────┘ │    │  └────────┬────────┘ │              │   │
│  │  │                      │    │           │          │              │   │
│  │  │  ┌────────────────┐ │    │  ┌────────▼────────┐ │              │   │
│  │  │  │ Edge Proxy VM  │ │    │  │ ATP Private     │ │              │   │
│  │  │  │ (NGINX)        │ │    │  │ Endpoint        │ │              │   │
│  │  │  └────────────────┘ │    │  │ (1521/TLS)      │ │              │   │
│  │  │                      │    │  └─────────────────┘ │              │   │
│  │  │  ┌────────────────┐ │    │                       │              │   │
│  │  │  │ Bastion Service│ │    │                       │              │   │
│  │  │  │ (SSH Tunnel)   │─┼────┼──► K8s API (6443)    │              │   │
│  │  │  └────────────────┘ │    │                       │              │   │
│  │  └──────────────────────┘    └──────────────────────┘              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌──────────────────┐   │
│  │ OCI Vault           │  │ ATP Database        │  │ Object Storage   │   │
│  │ - Master Key (AES)  │  │ - Autonomous DB     │  │ - Wallet Bucket  │   │
│  │ - App Secrets (JSON)│  │ - Data Guard (Paid) │  │ - Backups        │   │
│  │ - Instance Principal│  │ - Auto Backup       │  │                  │   │
│  └─────────────────────┘  └─────────────────────┘  └──────────────────┘   │
└────────────────────────────────────────────────────────────────────────────┘
```

## 📁 Project Structure

```
terraform/
├── live/                           # Environment configurations
│   ├── oci-staging/               # OCI production/staging environment
│   │   ├── network/               # VCN, subnets, gateways
│   │   ├── cluster/               # OKE control plane
│   │   ├── nodepool/              # Worker nodes
│   │   ├── bastion/               # Bastion service
│   │   ├── vault/                 # OCI Vault + secrets
│   │   ├── atp/                   # Autonomous Database
│   │   ├── wallet-bucket/         # ATP wallet storage
│   │   ├── edge-proxy/            # NGINX ingress VM
│   │   ├── load-balancer/         # Network LB
│   │   └── cluster-services/      # ArgoCD, ESO, cert-manager
│   └── local-dev/                 # Local Kind cluster for development
│
├── modules/                        # Reusable Terraform modules
│   ├── oci-network/               # VCN and networking
│   ├── oke-cluster/               # OKE control plane
│   ├── oke-nodepool/              # Worker node pools
│   ├── oci-vault/                 # Vault and secrets
│   ├── oci-atp/                   # Autonomous Database
│   ├── oci-bastion/               # Bastion service
│   ├── oci-edge-proxy/            # Edge proxy VM
│   ├── oci-network-lb/            # Network load balancer
│   └── cluster_services/          # Helm deployments
│
├── scripts/                        # Operational scripts
│   └── oci-bastion-kube-tunnel.sh # Bastion tunnel for kubectl
│
├── docs/                           # Documentation
│   ├── DISASTER_RECOVERY.md       # DR procedures and RTO/RPO
│   ├── SLI_SLO_SLA.md             # Service level definitions
│   ├── PRODUCTION_RUNBOOK.md      # Operational procedures
│   └── *.md                       # Component guides
│
└── archive/                        # Archived/reference configurations
```

## 🚀 Quick Start

### Prerequisites

1. **OCI CLI configured**:
   ```bash
   oci setup config
   oci iam region list  # Verify authentication
   ```

2. **Tools installed**:
   ```bash
   terraform version   # >= v1.14.3
   terragrunt version  # >= v0.96.1
   kubectl version --client # Client Version: v1.31.0
                            # Kustomize Version: v5.4.2
   ```

3. **Environment variables** (see `live/oci-staging/env.hcl`):
   ```bash
   export TF_VAR_compartment_id="ocid1.compartment.oc1..xxx"
   export TF_VAR_tenancy_id="ocid1.tenancy.oc1..xxx"
   ```

### Deployment

```bash
# 1. Deploy network layer
cd live/oci-staging/network
terragrunt apply

# 2. Deploy OKE cluster
cd ../cluster
terragrunt apply

# 3. Deploy node pool
cd ../nodepool
terragrunt apply

# 4. Deploy supporting services (vault, bastion, ATP)
cd ../vault && terragrunt apply
cd ../bastion && terragrunt apply
cd ../atp && terragrunt apply

# 5. Deploy cluster services (ArgoCD, ESO)
cd ../cluster-services
terragrunt apply
```

### Access Kubernetes API

```bash
# Via bastion tunnel (private endpoint)
export BASTION_OCID="ocid1.bastion.oc1..."
export K8S_PRIVATE_ENDPOINT="10.0.20.x"
./scripts/oci-bastion-kube-tunnel.sh

# Use generated kubeconfig
export KUBECONFIG=./kubeconfig.bastion
kubectl get nodes
```

## 📊 Component Dependencies

```
network
   │
   ├──► cluster ──► nodepool ──► vault ──► cluster-services
   │                   │           │              │
   │                   └───────────┼──────────────┘
   │                               │
   ├──► bastion                    │
   │                               │
   ├──► edge-proxy                 │
   │                               │
   ├──► load-balancer              │
   │                               │
   └──► atp ◄──────────────────────┘
```

## 💰 Production Tier Resources

| Resource | Configuration | Monthly Cost (Est.) |
|----------|--------------|---------------------|
| OKE Control Plane | Enhanced Cluster | ~$0 (included) |
| Worker Nodes | 3x E4.Flex (4 OCPU, 32GB) | ~$180 |
| NAT Gateway | Always-on | ~$33 |
| Network LB | 100 Mbps | ~$20 |
| ATP Database | 2 OCPU, 1TB, Data Guard | ~$800 |
| OCI Vault | Virtual Private | ~$50 |
| Bastion | Session-based | ~$0 |
| Object Storage | 100GB | ~$2 |
| **Total** | | **~$1,085/month** |

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [DISASTER_RECOVERY.md](docs/DISASTER_RECOVERY.md) | DR procedures, RTO/RPO targets, recovery runbooks |
| [SLI_SLO_SLA.md](docs/SLI_SLO_SLA.md) | Service level indicators, objectives, and agreements |
| [PRODUCTION_RUNBOOK.md](docs/PRODUCTION_RUNBOOK.md) | Day-2 operations, incident response, maintenance |
| [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) | Step-by-step deployment instructions |
| [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md) | Technical implementation details |
| [BASTION_TUNNEL_GUIDE.md](docs/BASTION_TUNNEL_GUIDE.md) | Bastion tunnel setup and usage |

## 🔐 Security Features

- **Private Kubernetes API**: Accessible only via Bastion tunnel
- **Instance Principal Authentication**: No credentials stored in cluster
- **TLS Everywhere**: ATP, K8s API, ingress all use TLS
- **Network Segmentation**: Public/private subnet isolation
- **Security Lists**: Restrictive ingress/egress rules
- **OCI Vault**: Centralized secrets with automatic rotation capability

## 📈 Monitoring

Monitoring is deployed separately via ArgoCD from the application repository. See [PRODUCTION_RUNBOOK.md](docs/PRODUCTION_RUNBOOK.md) for integration details.

**Stack Components** (deployed via ArgoCD):
- Prometheus (metrics collection)
- Grafana (dashboards and visualization)
- Alertmanager (alerting and notification)
- Loki (log aggregation)

## 🏷️ Related Documentation

- [OCI OKE Documentation](https://docs.oracle.com/en-us/iaas/Content/ContEng/home.htm)
- [Terraform OCI Provider](https://registry.terraform.io/providers/oracle/oci/latest/docs)
- [Terragrunt Documentation](https://terragrunt.gruntwork.io/docs/)

## 📄 License

See [LICENSE](LICENSE) for details.
