# Local Development Environment

Local Kind cluster with MetalLB LoadBalancer and nip.io DNS resolution.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Local Development Stack                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐                │
│  │   Browser    │────▶│   MetalLB    │────▶│ nginx-ingress│                │
│  │              │     │ LoadBalancer │     │  Controller  │                │
│  └──────────────┘     │ 172.18.255.x │     └──────┬───────┘                │
│                       └──────────────┘            │                         │
│                                                   ▼                         │
│  ┌────────────────────────────────────────────────────────────────┐        │
│  │              platform.172.18.255.200.nip.io                    │        │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────────┐       │        │
│  │  │/keycloak│  │  /argo  │  │/grafana │  │ /prometheus │       │        │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────────┘       │        │
│  └────────────────────────────────────────────────────────────────┘        │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────┐      │
│  │                    External Secrets Operator                      │      │
│  │                              │                                    │      │
│  │                              ▼                                    │      │
│  │  ┌──────────────────────────────────────────────────────────┐   │      │
│  │  │              LocalStack (AWS Emulation)                   │   │      │
│  │  │                  Secrets Manager                          │   │      │
│  │  └──────────────────────────────────────────────────────────┘   │      │
│  └──────────────────────────────────────────────────────────────────┘      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Quick Start

### Option A: With MetalLB (LoadBalancer + nip.io)

```bash
cd live/local-dev

# 1. Create Kind cluster
terragrunt apply --terragrunt-include-dir kind

# 2. Install MetalLB LoadBalancer
terragrunt apply --terragrunt-include-dir metallb

# 3. Deploy cluster services with MetalLB enabled
export TG_VAR_use_metallb=true
export TG_VAR_git_token="your-github-token"
terragrunt apply --terragrunt-include-dir cluster-services

# 4. Get the assigned LoadBalancer IP
INGRESS_IP=$(kubectl get svc -n ingress-nginx nginx-ingress-controller-ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Ingress IP: $INGRESS_IP"

# 5. (Optional) Re-apply with nip.io domain for host-based routing
export TG_VAR_ingress_domain="platform.${INGRESS_IP}.nip.io"
terragrunt apply --terragrunt-include-dir cluster-services

# 6. Access services
open "http://platform.${INGRESS_IP}.nip.io/argo"
```

### Option B: Without MetalLB (NodePort + localhost)

```bash
cd live/local-dev

# 1. Create Kind cluster
terragrunt apply --terragrunt-include-dir kind

# 2. Deploy cluster services (NodePort mode)
export TG_VAR_git_token="your-github-token"
terragrunt apply --terragrunt-include-dir cluster-services

# 3. Access via localhost (Kind extraPortMappings)
open http://localhost/argo
```

## Module Dependencies

```
kind/
  └── metallb/           (optional)
  └── cluster-services/
        ├── nginx-ingress
        ├── ArgoCD
        ├── LocalStack      (Kind only)
        ├── External Secrets (Kind only)
        └── ClusterSecretStore
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `TG_VAR_use_metallb` | Enable MetalLB LoadBalancer for nginx-ingress | `false` |
| `TG_VAR_ingress_domain` | nip.io domain (e.g., `platform.172.18.255.200.nip.io`) | `localhost` |
| `TG_VAR_git_token` | GitHub token for ArgoCD private repo access | (required) |
| `TG_VAR_argocd_repo_url` | ArgoCD App-of-Apps repository | `https://github.com/akthm/demo-k8s-gitops` |
| `TG_VAR_argocd_repo_path` | Path to apps in the repo | `apps/staging` |

## Troubleshooting

### MetalLB not assigning IP

```bash
# Check MetalLB controller logs
kubectl logs -n metallb-system -l app.kubernetes.io/component=controller

# Verify IPAddressPool exists
kubectl get ipaddresspool -n metallb-system

# Verify L2Advertisement exists
kubectl get l2advertisement -n metallb-system
```

### nip.io DNS not resolving

```bash
# Test DNS resolution
nslookup platform.172.18.255.200.nip.io

# Alternative: use sslip.io
export TG_VAR_ingress_domain="platform.172.18.255.200.sslip.io"
```

### LocalStack secrets not syncing

```bash
# Check LocalStack is running
kubectl get pods -n localstack

# List secrets in LocalStack
kubectl exec -n localstack deploy/local-stack-localstack -- awslocal secretsmanager list-secrets

# Check ClusterSecretStore status
kubectl get clustersecretstore aws-secrets-manager -o yaml
```

## Destroy

```bash
cd live/local-dev
terragrunt run-all destroy
```
