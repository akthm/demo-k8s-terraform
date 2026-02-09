# Bastion Tunnel Implementation - Summary

## What Was Implemented

This implementation adds secure access to the private OKE Kubernetes API endpoint via OCI Bastion Service for Terraform/Terragrunt deployments.

## Changes Made

### 1. Bastion Tunnel Script
**File**: `scripts/oci-bastion-kube-tunnel.sh`

- Creates OCI Bastion port-forwarding session
- Establishes SSH tunnel: `localhost:6443` → `10.0.10.165:6443`
- Auto-generates SSH keys if missing
- Validates tunnel connectivity
- Creates kubeconfig for tunnel access

**Features**:
- ✅ Idempotent (reuses existing tunnel if working)
- ✅ Error handling with clear messages
- ✅ Automatic cleanup on failure
- ✅ Configurable via environment variables

### 2. Terragrunt Before Hook
**File**: `live/oci-staging/cluster-services/terragrunt.hcl`

Added `before_hook` that runs before `apply`, `plan`, `destroy`:

```hcl
terraform {
  before_hook "bastion_tunnel" {
    commands = ["apply", "plan", "destroy"]
    execute  = ["bash", "-c", "...script invocation..."]
  }
}
```

### 3. Provider Configuration
**File**: `live/oci-staging/cluster-services/terragrunt.hcl`

Updated Kubernetes and Helm providers to use localhost tunnel:

```hcl
provider "kubernetes" {
  host = "https://127.0.0.1:6443"  # Tunnel endpoint
  cluster_ca_certificate = "..."
  exec {
    command = "oci"
    args    = ["ce", "cluster", "generate-token", ...]
  }
}
```

### 4. Environment Configuration
**File**: `live/oci-staging/env.hcl`

Added bastion OCID to environment locals:

```hcl
locals {
  bastion_ocid = "ocid1.bastion.oc1.il-jerusalem-1.amaaaaaa..."
}
```

### 5. Documentation

Created comprehensive guides:

| File | Purpose |
|------|---------|
| `docs/BASTION_TUNNEL_GUIDE.md` | Complete bastion tunnel documentation |
| `docs/PUBLIC_API_SETUP.md` | Alternative public API approach |
| `docs/CLUSTER_SERVICES_DEPLOYMENT.md` | Deployment guide with tunnel |
| `scripts/README.md` | Scripts directory documentation |

## How It Works

```
┌──────────────────────────────────────────────────────────┐
│ 1. User runs: terragrunt apply                           │
└────────────────┬─────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────┐
│ 2. Before hook executes oci-bastion-kube-tunnel.sh       │
│    - Creates bastion session (3hr TTL)                   │
│    - Starts SSH tunnel in background                     │
│    - Generates kubeconfig.bastion                        │
└────────────────┬─────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────┐
│ 3. Terraform providers initialized                       │
│    - kubernetes provider → https://127.0.0.1:6443        │
│    - helm provider → https://127.0.0.1:6443              │
└────────────────┬─────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────┐
│ 4. Helm releases deployed via tunnel                     │
│    - external-secrets (ESO)                              │
│    - metrics-server                                      │
│    - argocd (optional)                                   │
│    - nginx-ingress (optional)                            │
│    - cert-manager (optional)                             │
└──────────────────────────────────────────────────────────┘
```

## Network Flow

```
Terraform/Helm Provider
         │
         │ HTTPS
         ▼
   localhost:6443
         │
         │ SSH Tunnel
         │ (created by before_hook)
         ▼
  Bastion Service
  (Public Subnet)
         │
         │ Port Forwarding Session
         │ (3hr TTL)
         ▼
   K8s API Server
   10.0.10.165:6443
   (Private Subnet)
```

## Security Model

### Authentication Layers

1. **OCI IAM**: Bastion session creation requires OCI user/instance principal auth
2. **SSH Key**: Bastion session requires matching SSH public key
3. **OCI Token**: K8s API requires `oci ce cluster generate-token`
4. **TLS**: All traffic encrypted via TLS (API cert)

### Attack Surface

- ✅ K8s API not exposed to internet (private endpoint)
- ✅ Bastion sessions time-limited (3hr TTL)
- ✅ All bastion access logged in OCI Audit
- ✅ SSH tunnel local-only (127.0.0.1)
- ⚠️ Local users can access tunnel (standard localhost security)

## Usage

### Deploy Cluster Services

```bash
cd live/oci-staging/cluster-services
terragrunt apply
```

That's it! The hook handles everything automatically.

### Manual Tunnel Creation

```bash
export BASTION_OCID="ocid1.bastion.oc1..."
export K8S_PRIVATE_ENDPOINT="10.0.10.165"
export CLUSTER_ID="ocid1.cluster.oc1..."
export OCI_REGION="il-jerusalem-1"

./scripts/oci-bastion-kube-tunnel.sh
```

### Check Tunnel Status

```bash
# Check if port 6443 is listening
lsof -i :6443

# Test connectivity
timeout 2 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/6443"

# Use tunnel
KUBECONFIG=./kubeconfig.bastion kubectl get nodes
```

### Stop Tunnel

```bash
pkill -f 'ssh.*6443:10.0.10.165:6443'
```

## Configuration Options

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BASTION_OCID` | from env.hcl | Bastion OCID |
| `K8S_PRIVATE_ENDPOINT` | 10.0.10.165 | K8s API private IP |
| `K8S_PORT` | 6443 | Target port |
| `LOCAL_K8S_PORT` | 6443 | Local tunnel port |
| `BASTION_TTL` | 10800 | Session TTL (seconds) |
| `SSH_KEY_PATH` | ~/.ssh/oci_bastion_k8s | SSH key location |
| `CLUSTER_ID` | from dependency | Cluster OCID |
| `OCI_REGION` | il-jerusalem-1 | OCI region |

### Customization

To change settings, set environment variables before running terragrunt:

```bash
export BASTION_TTL="7200"  # 2 hours instead of 3
export LOCAL_K8S_PORT="16443"  # Use different local port

cd live/oci-staging/cluster-services
terragrunt apply
```

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| Port 6443 in use | `pkill -f 'ssh.*6443'` |
| Bastion session limit | Delete old sessions via OCI Console |
| SSH key missing | Script auto-generates at ~/.ssh/oci_bastion_k8s |
| Tunnel timeout | Re-run terragrunt (creates new session) |
| OCI CLI error | Check `~/.oci/config` and credentials |

### Debug Mode

```bash
# Enable bash debug output
cd live/oci-staging/cluster-services

# Edit terragrunt.hcl, change execute line:
execute = ["bash", "-x", "-c", "..."]

# Run
terragrunt plan
```

## Alternative: Public API

If bastion tunnel approach doesn't fit your use case, see [PUBLIC_API_SETUP.md](docs/PUBLIC_API_SETUP.md) for making the K8s API publicly accessible.

**When to use public API instead**:
- ArgoCD needs direct access for GitOps
- CI/CD pipelines from external services
- Multiple developers need simple kubectl access
- Don't want to manage session TTLs

## Cost Impact

**Additional costs**: $0

- Bastion service: ~$1.50/month (already deployed)
- Port-forwarding sessions: FREE (included)
- SSH tunnels: FREE
- Data transfer: FREE (same region)

## Files Created

```
terraform/
├── scripts/
│   ├── oci-bastion-kube-tunnel.sh     [NEW] - Main script
│   └── README.md                       [NEW] - Scripts documentation
├── docs/
│   ├── BASTION_TUNNEL_GUIDE.md        [NEW] - Tunnel guide
│   ├── PUBLIC_API_SETUP.md            [NEW] - Public API alternative
│   └── CLUSTER_SERVICES_DEPLOYMENT.md [NEW] - Deployment guide
└── live/oci-staging/
    ├── env.hcl                         [MODIFIED] - Added bastion_ocid
    └── cluster-services/
        └── terragrunt.hcl              [MODIFIED] - Added before_hook
```

## Testing Checklist

Before deploying to production:

- [ ] Verify bastion is active: `oci bastion bastion get --bastion-id <id>`
- [ ] Test script manually: `./scripts/oci-bastion-kube-tunnel.sh`
- [ ] Check script creates tunnel: `lsof -i :6443`
- [ ] Verify kubectl works: `KUBECONFIG=./kubeconfig.bastion kubectl get nodes`
- [ ] Test terragrunt plan: `cd cluster-services && terragrunt plan`
- [ ] Review what will be deployed
- [ ] Deploy: `terragrunt apply`
- [ ] Verify services: `kubectl get pods -A`

## Next Steps

1. **Deploy cluster services**:
   ```bash
   cd live/oci-staging/cluster-services
   terragrunt apply
   ```

2. **Verify External Secrets Operator**:
   ```bash
   kubectl get pods -n external-secrets
   kubectl get clustersecretstore oci-vault
   ```

3. **Deploy ATP**:
   ```bash
   cd ../atp
   terragrunt apply
   ```

4. **Update vault secrets** with ATP connection details

5. **Test ESO synchronization**:
   ```bash
   kubectl get externalsecrets -A
   ```

## References

- [OCI Bastion Service](https://docs.oracle.com/en-us/iaas/Content/Bastion/home.htm)
- [OCI Bastion Port Forwarding](https://docs.oracle.com/en-us/iaas/Content/Bastion/Tasks/managingsessions.htm#port-forwarding)
- [Terragrunt Hooks](https://terragrunt.gruntwork.io/docs/features/hooks/)
- [OKE Private Clusters](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengaccessingclusterkubectl.htm)

## Support

For issues or questions:
1. Check [BASTION_TUNNEL_GUIDE.md](docs/BASTION_TUNNEL_GUIDE.md) troubleshooting section
2. Review OCI Bastion session logs in OCI Console
3. Enable debug mode (`bash -x`) for detailed output
4. Check active bastion sessions: `oci bastion session list`
