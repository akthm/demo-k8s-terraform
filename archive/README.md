# AWS EKS Infrastructure as Code - Best Practices Guide

## 📋 Overview

This Terraform project deploys a production-ready AWS EKS cluster with integrated services:
- **VPC & Networking** - HA-ready networking across multiple AZs
- **EKS Cluster** - Managed Kubernetes with addons (CoreDNS, VPC-CNI, EBS CSI)
- **Cluster Services** - ArgoCD, External Secrets Operator, AWS Load Balancer Controller

---

## IMPORANT NOTES
### EXTERNALSECRETS, ARGOCD Auto Provisioning disabled for staging, manually provision through helm after EKS creation.


## 🏗️ Project Structure

```
terraform/
├── main.tf                          # ROOT: Orchestrates all modules
├── variables.tf                     # ROOT: All input variables
├── providers.tf                     # ROOT: AWS provider + backend config
├── terraform.tfvars                 # ROOT: Variable values (environment-specific)
├── outputs.tf                       # ROOT: Final outputs
└── modules/
    ├── eks/                         # EKS Cluster Module
    │   ├── MAIN.tf                  # EKS & addons definitions
    │   ├── variables.tf             # Module inputs
    │   ├── outputs.tf               # Cluster outputs (used by cluster_services)
    │   ├── providers.tf             # AWS provider
    │   └── modules/
    │       ├── network/             # VPC networking
    │       │   ├── main.tf
    │       │   ├── outputs.tf
    │       │   └── variables.tf
    │       └── ebs-csi-storageclass/  # Storage configuration
    │           ├── main.tf
    │           ├── provider.tf       # Kubernetes provider
    │           ├── outputs.tf
    │           └── variables.tf
    │
    └── cluster_services/            # Post-cluster services
        ├── Main.tf                  # Helm releases for ArgoCD, ESO, LB Controller
        ├── Provider.tf              # Kubernetes & Helm providers
        ├── Inputs.tf                # Module variables
        ├── IAM.tf                   # External Secrets IAM/IRSA
        ├── load_balancer.tf         # Load Balancer Controller IAM/IRSA
        ├── external_secrets.tf      # ESO ClusterSecretStore
        └── argo_cd.tf               # ArgoCD bootstrap manifests
```

---

## 🚀 Quick Start

### Prerequisites
```bash
# 1. Install Terraform
terraform version  # >= 1.5.0

# 2. AWS credentials configured
aws configure

# 3. kubectl installed (for post-deployment validation)
kubectl version --client
```

### Deploy the Infrastructure

```bash
# 1. Navigate to project root
cd /home/akthm/Devops/portfolio/terraform

# 2. Initialize Terraform (downloads providers & modules)
terraform init

# 3. Review the planned changes
terraform plan -var-file="terraform.tfvars"

# 4. Apply the infrastructure
terraform apply -var-file="terraform.tfvars"

# 5. Configure kubectl
eval $(terraform output -raw kubeconfig_command)

# 6. Verify cluster connectivity
kubectl get nodes
kubectl get pods -A
```

---



## 📊 Data Flow & Dependencies

```
terraform.tfvars (Input Variables)
        ↓
   variables.tf (Validation + Schema)
        ↓
    providers.tf (AWS Provider)
        ↓
     main.tf (Orchestration)
        ├→ modules/eks/MAIN.tf (Creates VPC + EKS)
        │   ├→ network/main.tf (VPC, Subnets, IGW)
        │   ├→ EKS cluster resources
        │   └→ EBS CSI IRSA role
        │
        └→ modules/cluster_services/Main.tf (Services)
            ├→ Provider.tf (Kubernetes/Helm - uses EKS outputs)
            ├→ IAM.tf (External Secrets IRSA)
            ├→ load_balancer.tf (LB Controller IRSA)
            ├→ Helm releases (ArgoCD, ESO, LB Controller)
            └→ Kubernetes manifests (ClusterSecretStore, App-of-Apps)
```

**Critical Point**: `cluster_services` module MUST wait for EKS completion.
This is enforced via:
```terraform
depends_on = [module.eks]  # In root main.tf
```

---

## 🔐 Best Practices Implemented

### 1. **Remote State Management**
```bash
# Enable S3 backend for production
terraform init -backend-config="bucket=your-bucket" \
               -backend-config="key=infrastructure/terraform.tfstate" \
               -backend-config="region=ap-south-1"
```

### 2. **IRSA (IAM Roles for Service Accounts)**
All service accounts use IRSA for least-privilege access:
- External Secrets Operator → Read Secrets Manager
- AWS Load Balancer Controller → Manage ALBs/NLBs
- EBS CSI Driver → Manage EBS volumes

### 3. **Tagging Strategy**
All resources tagged via:
```terraform
default_tags {
  tags = var.common_tags
}
```
Enables cost allocation, resource tracking, and automation.

### 4. **Variable Validation**
All critical inputs validated at declaration time:
- CIDR blocks checked for validity
- AWS regions validated against format
- Kubernetes versions restricted to known formats

### 5. **Explicit Dependency Ordering**
Services deployed in correct sequence:
1. VPC → Subnets
2. EKS cluster → OIDC provider
3. EBS CSI → Storage defaults
4. Kubernetes providers (need EKS endpoint/token)
5. Helm releases → Kubernetes manifests

### 6. **Environment-Specific Configuration**
Use separate `tfvars` files for different environments:
```bash
# Staging
terraform apply -var-file="terraform.staging.tfvars"

# Production
terraform apply -var-file="terraform.prod.tfvars"
```

### 7. **Sensitive Output Protection**
```terraform
output "cluster_certificate_authority_data" {
  sensitive = true  # Prevents display in terraform output
  value     = module.eks.cluster_certificate_authority_data
}
```

---

## 🐛 Troubleshooting

### Issue: "Blocks of type 'kubernetes' are not expected here"
**Cause**: Kubernetes provider defined outside of `provider` block
**Solution**: Ensure all provider configurations are in the `provider "name" {}` block format

### Issue: "module.iam_aws_lb_controller.role_arn not found"
**Cause**: IAM module output not properly exposed
**Solution**: Verify `load_balancer.tf` defines: `output "aws_lb_controller_role_arn"`

### Issue: Terraform plan takes long time or times out
**Cause**: Module dependencies not explicitly declared
**Solution**: Add `depends_on = [module.eks]` in `cluster_services` call in root `main.tf`

### Issue: "Unable to reach Kubernetes API"
**Cause**: Kubernetes provider tries to connect before cluster is ready
**Solution**: Ensure `cluster_services` module waits for EKS completion (handled by root `depends_on`)

---

## 📝 Variable Reference

| Variable | Type | Purpose | Example |
|----------|------|---------|---------|
| `common_tags` | object | Tags all resources | `{ owner = "dakar", ... }` |
| `region` | string | AWS deployment region | `ap-south-1` |
| `vpc_cidrs` | string | VPC CIDR block | `10.0.0.0/16` |
| `ha` | number | Availability zones | `2` |
| `cluster_version` | string | Kubernetes version | `1.31` |
| `node_type` | string | EC2 instance type | `t3a.medium` |
| `argocd_app_of_apps_repo_url` | string | Git repo for apps | `https://github.com/org/k8s-apps` |
| `argocd_app_of_apps_repo_path` | string | Path within Git repo | `apps/staging` |

---

## 🚫 What NOT to Do

1. **Don't commit `terraform.tfvars` with secrets** → Use `.gitignore`
2. **Don't modify modules in `.terraform/` directory** → Changes will be lost on `terraform init`
3. **Don't hardcode AWS account IDs or secrets** → Use variables/data sources
4. **Don't skip `terraform plan` before `apply`** → Review changes first
5. **Don't delete `.terraform.lock.hcl`** → Keep for reproducible deployments

---

## 📚 Additional Resources

- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS EKS Module](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws)
- [IRSA Best Practices](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [EKS Workshop](https://www.eksworkshop.com/)

---

## 🎯 Next Steps

1. **Customize `terraform.tfvars`** with your environment values
2. **Set up S3 backend** for production deployments
3. **Create CI/CD pipeline** (GitHub Actions, GitLab CI, etc.)
4. **Deploy workloads** via ArgoCD using "App of Apps" pattern
5. **Monitor with CloudWatch/Prometheus** for production readiness

