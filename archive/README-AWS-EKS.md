# AWS EKS Infrastructure with ArgoCD GitOps

## 📋 Project Overview

Production-ready AWS EKS cluster infrastructure deployed via Terraform with GitOps capabilities. This project provisions a complete Kubernetes environment with minimal essential services, designed for bootstrapping and automated application deployment through ArgoCD.

**Core Infrastructure:**
- **VPC & Networking** - Multi-AZ high-availability networking with public/private subnets
- **EKS Cluster** - Managed Kubernetes with worker nodes and essential addons
- **NGINX Ingress Controller** - HTTP LoadBalancer for routing traffic to services
- **ArgoCD** - GitOps continuous deployment engine with App-of-Apps pattern
- **External Secrets Operator** - AWS Secrets Manager integration for secure secrets management

**Architecture Philosophy:**
- Terraform provisions minimal bootstrap infrastructure
- ArgoCD manages all application workloads from Git
- Infrastructure as Code (IaC) for reproducibility
- GitOps for continuous deployment and declarative configuration

---

## 🚀 Quick Start Guide

### Prerequisites

1. **AWS CLI configured** with credentials:
   ```bash
   aws configure
   # Provide: Access Key ID, Secret Access Key, Region (ap-south-1), Output format (json)
   ```

2. **Tools installed:**
   ```bash
   terraform version  # >= 1.5.0
   kubectl version --client
   aws --version
   ```

3. **GitHub Personal Access Token**:
   ```bash
   # Create token at GitHub Settings → Developer settings → Personal access tokens
   # Required scope: repo (for private repositories)
   export TF_VAR_git_token="ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
   ```

---

### Provisioning Steps

#### Step 1: Initialize Terraform
```bash
cd /home/akthm/Devops/portfolio/terraform
terraform init
```

#### Step 2: Deploy EKS Cluster Only (Phase 1)
```bash
# Deploy VPC, networking, and EKS cluster
terraform apply -target=module.eks -var-file="terraform.tfvars" -auto-approve

# This takes ~15-20 minutes and creates:
# - VPC with public/private subnets
# - Internet Gateway, NAT Gateways
# - EKS cluster with worker nodes
# - EBS CSI driver, External Secrets Operator
```

**Why Phase 1?** The Kubernetes and Helm providers need the EKS cluster endpoint before they can initialize, avoiding circular dependencies.

#### Step 3: Configure kubectl
```bash
# Get the command from Terraform output
terraform output kubeconfig_command

# Example output: aws eks update-kubeconfig --region ap-south-1 --name akthm-cluster
# Run the command:
aws eks update-kubeconfig --region ap-south-1 --name akthm-cluster

# Verify cluster access
kubectl get nodes
# Expected: 2 nodes in Ready state
```

#### Step 4: Deploy Cluster Services (Phase 2)
```bash
# Deploy NGINX Ingress and ArgoCD
terraform apply -var-file="terraform.tfvars" -auto-approve

# This takes ~5-10 minutes and creates:
# - NGINX Ingress Controller (AWS Network LoadBalancer)
# - ArgoCD server (HA with 2 replicas)
# - ArgoCD ingress (path-based routing at /argo)
```

#### Step 5: Get LoadBalancer DNS
```bash
# Option A: From Terraform output
terraform output nginx_loadbalancer_info

# Option B: Direct kubectl command
kubectl -n ingress-nginx get svc ingress-nginx-controller

# Look for EXTERNAL-IP column (e.g., a1b2c3d4-12345.ap-south-1.elb.amazonaws.com)
# Takes 2-5 minutes to provision
```

#### Step 6: Get ArgoCD Admin Credentials
```bash
# Get password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo

# Access ArgoCD UI
# URL: http://<LOADBALANCER-DNS>/argo
# Username: admin
# Password: <from command above>
```

**Example Access:**
```
URL: http://a1b2c3d4-12345.ap-south-1.elb.amazonaws.com/argo
Username: admin
Password: xJ9kL2pQ8mN5v
```

---

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────┐
│               AWS Cloud (ap-south-1)                 │
│                                                      │
│  ┌────────────────────────────────────────────────┐ │
│  │  VPC (10.0.0.0/16)                             │ │
│  │                                                │ │
│  │  ┌──────────────┐      ┌──────────────┐       │ │
│  │  │ AZ-1         │      │ AZ-2         │       │ │
│  │  │ Public: /24  │      │ Public: /24  │       │ │
│  │  │ Private: /24 │      │ Private: /24 │       │ │
│  │  └──────────────┘      └──────────────┘       │ │
│  │         │                      │               │ │
│  │         └──────────┬───────────┘               │ │
│  │                    │                           │ │
│  │  ┌─────────────────▼────────────────────────┐  │ │
│  │  │  EKS Cluster (Kubernetes 1.34)          │  │ │
│  │  │                                         │  │ │
│  │  │  ┌───────────────────────────────────┐  │  │ │
│  │  │  │  NGINX Ingress (Network LB)       │  │  │ │
│  │  │  │  └─► /argo → ArgoCD Server        │  │  │ │
│  │  │  └───────────────────────────────────┘  │  │ │
│  │  │                                         │  │ │
│  │  │  ┌───────────────────────────────────┐  │  │ │
│  │  │  │  ArgoCD (GitOps Engine)           │  │  │ │
│  │  │  │  - Syncs from Git Repository      │  │  │ │
│  │  │  │  - App-of-Apps pattern            │  │  │ │
│  │  │  │  - Manages all workloads          │  │  │ │
│  │  │  └───────────────────────────────────┘  │  │ │
│  │  │                                         │  │ │
│  │  │  ┌───────────────────────────────────┐  │  │ │
│  │  │  │  External Secrets Operator        │  │  │ │
│  │  │  │  - AWS Secrets Manager sync       │  │  │ │
│  │  │  │  - IRSA authentication            │  │  │ │
│  │  │  └───────────────────────────────────┘  │  │ │
│  │  │                                         │  │ │
│  │  │  ┌───────────────────────────────────┐  │  │ │
│  │  │  │  Your Applications                │  │  │ │
│  │  │  │  (Managed by ArgoCD from Git)     │  │  │ │
│  │  │  └───────────────────────────────────┘  │  │ │
│  │  └─────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘
```

---

## 📊 Build Explanation

### Data Flow

```
1. terraform.tfvars (user inputs)
        ↓
2. variables.tf (validation & type checking)
        ↓
3. providers.tf (AWS provider initialization)
        ↓
4. main.tf (orchestration layer)
        ├─► module.eks
        │    ├─► network/ (VPC, subnets, routing)
        │    ├─► EKS cluster (control plane + worker nodes)
        │    ├─► EKS addons (CoreDNS, VPC-CNI, EBS CSI)
        │    ├─► External Secrets Operator (via Blueprints)
        │    └─► OIDC provider (for IRSA)
        │
        └─► module.cluster_services
             ├─► Kubernetes provider (uses EKS endpoint)
             ├─► Helm provider (uses EKS endpoint)
             ├─► NGINX Ingress Controller (Helm release)
             ├─► ArgoCD (Helm release with HA)
             ├─► ArgoCD ingress (Kubernetes manifest)
             └─► ArgoCD App-of-Apps (bootstraps Git sync)
```

---

### Module: `eks/`

**Purpose:** Provisions EKS cluster and foundational infrastructure.

**Components:**

1. **Network Module** (`modules/eks/modules/network/`)
   - VPC with configurable CIDR
   - Public subnets (one per AZ, tagged for LoadBalancers)
   - Private subnets (one per AZ, tagged for internal services)
   - Internet Gateway for public subnet egress
   - NAT Gateways (one per AZ) for private subnet egress
   - Route tables and associations

2. **EKS Cluster** (AWS EKS module)
   - Managed Kubernetes control plane
   - Worker node groups (t3a.large by default, scalable)
   - Cluster security groups
   - OIDC provider for IRSA (IAM Roles for Service Accounts)

3. **EKS Addons** (via EKS Blueprints Addons)
   - **CoreDNS** - Cluster DNS
   - **VPC-CNI** - AWS VPC networking for pods
   - **kube-proxy** - Network proxy on nodes
   - **EBS CSI Driver** - Persistent volume provisioning
   - **External Secrets Operator** - AWS Secrets Manager integration

4. **EBS CSI StorageClass** (`modules/eks/modules/ebs-csi-storageclass/`)
   - Default storage class using EBS gp3 volumes
   - Encrypted at rest
   - WaitForFirstConsumer binding mode (topology-aware)

**Key Outputs:**
- Cluster name, endpoint, certificate authority
- OIDC provider ARN and issuer URL
- Security group IDs
- kubeconfig command

---

### Module: `cluster_services/`

**Purpose:** Bootstrap essential services for GitOps and traffic routing.

**Components:**

1. **NGINX Ingress Controller** (Helm release)
   - Chart: `ingress-nginx/ingress-nginx` v4.10.0
   - Service type: LoadBalancer (creates AWS Network Load Balancer)
   - Namespace: `ingress-nginx`
   - Purpose: Routes HTTP traffic to services via path-based rules

2. **ArgoCD** (Helm release)
   - Chart: `argo/argo-cd` v6.0.0
   - High Availability: 2 replicas for server and repo-server
   - Namespace: `argocd`
   - Git repository credentials injected via Kubernetes secret
   - Ingress configured for path `/argo`

3. **ArgoCD Ingress** (Kubernetes manifest)
   - Routes `http://<LoadBalancer>/argo` → ArgoCD server
   - No TLS/HTTPS (simplified for development)
   - Path rewrite: strips `/argo` prefix before forwarding

4. **ArgoCD App-of-Apps** (Kubernetes Application manifest)
   - Bootstraps GitOps by pointing ArgoCD at your Git repository
   - Auto-syncs applications from configured path
   - Enables declarative application management

**Key Outputs:**
- ArgoCD namespace and access URL
- NGINX LoadBalancer info command
- Admin password retrieval command

---

### Root Module (`main.tf`)

**Purpose:** Orchestrates all modules and manages dependencies.

**Key Responsibilities:**
1. Data source for EKS cluster authentication token
2. Invokes `module.eks` with required variables
3. Configures Kubernetes and Helm providers (using EKS outputs)
4. Adds 30-second wait after cluster creation (ensures readiness)
5. Invokes `module.cluster_services` with cluster details
6. Exposes consolidated outputs for end-user access

**Dependency Chain:**
```
module.eks
   ↓
time_sleep.wait_for_cluster
   ↓
module.cluster_services
```

---

### External Secrets Operator Integration

**Purpose:** Sync secrets from AWS Secrets Manager to Kubernetes secrets.

**Architecture:**

```
AWS Secrets Manager (ap-south-1)
  ├── staging/backend/database     (MySQL credentials)
  ├── staging/backend/flask-app    (Flask SECRET_KEY, API keys)
  ├── staging/backend/admin        (Admin user credentials)
  └── staging/backend/jwt-keys     (RSA keys for JWT signing)
         ↓
ClusterSecretStore (IRSA authentication)
         ↓
ExternalSecret resources (define mappings)
         ↓
Kubernetes Secrets (auto-created and synced)
         ↓
Application Pods (mount secrets as env vars or volumes)
```

**Components:**

1. **External Secrets Operator** (deployed via EKS Blueprints Addons)
   - Namespace: `external-secrets`
   - Service Account: `external-secrets-sa` (with IRSA role)
   - Pods: operator, cert-controller, webhook

2. **ClusterSecretStore** (Kubernetes resource)
   - Defines connection to AWS Secrets Manager
   - Uses IRSA for authentication (no access keys needed)
   - Region: `ap-south-1`

3. **ExternalSecret** (Kubernetes resources - deployed via GitOps)
   - Define which AWS secret to sync
   - Map AWS secret keys to Kubernetes secret keys
   - Auto-refresh every 1 hour (configurable)

4. **IRSA Role** (IAM role for service account)
   - Attached to `external-secrets-sa` service account
   - Policy allows `secretsmanager:GetSecretValue` for `staging/backend/*`
   - Least-privilege access (scoped to specific secret paths)

**Setup Script:** `create-secrets.sh`
- Creates AWS Secrets Manager secrets with auto-generated passwords
- Outputs secrets ARNs and credential values

**Validation Script:** `post-terraform-validation.sh`
- Checks External Secrets Operator health
- Verifies ClusterSecretStore is Ready
- Validates ExternalSecrets are syncing
- Auto-fixes common issues (kubeconfig, StorageClass, pod restarts)

---

### Variables

| Variable | Type | Required | Default | Example | Description |
|----------|------|----------|---------|---------|-------------|
| `common_tags` | object | ✅ | - | `{ owner = "akthm", ... }` | Tags applied to all AWS resources |
| `region` | string | ✅ | - | `ap-south-1` | AWS region for deployment |
| `vpc_cidrs` | string | ✅ | - | `10.0.0.0/16` | VPC CIDR block |
| `ha` | number | ✅ | - | `2` | Number of Availability Zones (1-3) |
| `cluster_version` | string | ✅ | - | `1.34` | Kubernetes version |
| `node_type` | string | ✅ | - | `t3a.large` | EC2 instance type for worker nodes |
| `argocd_repo_url` | string | ✅ | - | `https://github.com/org/gitops` | Git repository URL for ArgoCD |
| `argocd_repo_path` | string | ❌ | `apps` | `apps/staging` | Path within repo to application manifests |
| `argocd_target_revision` | string | ❌ | `main` | `main` | Git branch/tag to sync from |
| `argocd_version` | string | ❌ | `6.0.0` | `6.0.0` | ArgoCD Helm chart version |
| `git_token` | string | ✅ | - | `ghp_xxxx...` | GitHub/GitLab Personal Access Token (sensitive) |

---

## 📁 Project Structure

```
terraform/
├── main.tf                      # Root orchestration (calls modules)
├── variables.tf                 # Input variable definitions (11 variables)
├── providers.tf                 # AWS, Kubernetes, Helm providers
├── terraform.tfvars             # Variable values (environment-specific)
│
├── modules/
│   ├── eks/                     # EKS Cluster Module
│   │   ├── MAIN.tf              # EKS cluster, addons, External Secrets
│   │   ├── variables.tf         # Module inputs
│   │   ├── outputs.tf           # Cluster details exported
│   │   └── modules/
│   │       ├── network/         # VPC, subnets, IGW, NAT
│   │       │   ├── main.tf
│   │       │   ├── outputs.tf
│   │       │   └── variables.tf
│   │       └── ebs-csi-storageclass/  # Default storage class
│   │           ├── main.tf
│   │           ├── outputs.tf
│   │           ├── provider.tf
│   │           └── variables.tf
│   │
│   └── cluster_services/        # Bootstrap Services
│       ├── Main.tf              # NGINX Ingress + ArgoCD
│       ├── variables.tf         # Module inputs (9 variables)
│       ├── outputs.tf           # Access commands and URLs
│       └── Provider.tf          # Kubernetes/Helm providers
│
├── create-secrets.sh            # AWS Secrets Manager initialization
└── post-terraform-validation.sh # Automated validation script
```

---

## 🔐 Secrets Management

### AWS Secrets Manager

All sensitive application credentials are stored in AWS Secrets Manager and synced to Kubernetes via External Secrets Operator.

**Created Secrets:**
1. **`staging/backend/database`** - MySQL credentials
2. **`staging/backend/flask-app`** - Flask SECRET_KEY, API keys
3. **`staging/backend/admin`** - Admin user credentials
4. **`staging/backend/jwt-keys`** - RSA keys for JWT signing

**Setup:**
```bash
# Create all secrets with auto-generated passwords
./create-secrets.sh

# View created secrets
aws secretsmanager list-secrets --region ap-south-1 \
  --filters Key=name,Values=staging/backend
```

---

## 🔍 Verification

### Check All Services Running

```bash
# EKS cluster nodes
kubectl get nodes

# External Secrets Operator
kubectl get pods -n external-secrets

# NGINX Ingress Controller
kubectl get pods -n ingress-nginx

# ArgoCD
kubectl get pods -n argocd

# All applications managed by ArgoCD
kubectl get applications -n argocd
```

### Run Validation Script

```bash
./post-terraform-validation.sh

# Auto-validates and fixes:
# - Kubernetes connectivity
# - External Secrets Operator health
# - ClusterSecretStore Ready status
# - AWS Secrets Manager secrets exist
# - ExternalSecrets syncing properly
# - StorageClass availability
# - Pod health and readiness
```

---

## 🐛 Troubleshooting

### Issue: `terraform plan` shows errors for kubernetes_manifest

**Cause:** Terraform validates manifests during plan, but cluster doesn't exist yet.

**Solution:** This is expected behavior. Use two-phase deployment:
```bash
terraform apply -target=module.eks    # Phase 1
terraform apply                       # Phase 2
```

---

### Issue: ArgoCD UI not accessible

**Checks:**
1. LoadBalancer provisioning takes 2-5 minutes:
   ```bash
   kubectl -n ingress-nginx get svc ingress-nginx-controller -w
   ```

2. Verify ArgoCD pods are running:
   ```bash
   kubectl get pods -n argocd
   ```

**Solution:** Wait for LoadBalancer to provision, then access via:
```
http://<EXTERNAL-IP>/argo
```

---

### Issue: External Secrets not syncing

**Checks:**
1. Verify ClusterSecretStore is Ready:
   ```bash
   kubectl get clustersecretstore aws-secrets-manager
   ```

2. Check External Secrets Operator logs:
   ```bash
   kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
   ```

**Common Fixes:**
- Ensure secret path in AWS matches `remoteRef.key` in ExternalSecret
- Verify IRSA role has `secretsmanager:GetSecretValue` permission

---

### Issue: kubectl commands fail

**Cause:** kubeconfig not configured or expired.

**Solution:**
```bash
# Reconfigure kubeconfig
eval $(terraform output -raw kubeconfig_command)

# Verify
kubectl cluster-info
```

---

## 🧹 Cleanup

### Destroy All Infrastructure

```bash
# Destroy all resources (warning: irreversible!)
terraform destroy -var-file="terraform.tfvars"

# Confirm by typing: yes
```

**Order of Deletion:**
1. ArgoCD and NGINX Ingress (Helm releases)
2. Kubernetes manifests
3. EKS addons
4. Worker node groups
5. EKS cluster
6. NAT Gateways, Internet Gateway
7. VPC and subnets

---

## 🎯 Best Practices Implemented

1. **Infrastructure as Code** - All resources defined declaratively in Terraform
2. **GitOps-First** - Terraform provisions minimal bootstrap, ArgoCD manages apps
3. **Security** - IRSA for pod-level IAM permissions, encrypted EBS volumes
4. **High Availability** - Multi-AZ deployment, ArgoCD with 2 replicas
5. **Cost Optimization** - Smaller instance types by default, auto-scaling node groups
6. **Observability** - All pods emit logs, ArgoCD UI for deployment visibility

---

## 📚 Additional Resources

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [External Secrets Operator](https://external-secrets.io/)

---

**Last Updated:** November 23, 2025

