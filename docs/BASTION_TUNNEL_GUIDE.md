# OKE Private API Access via Bastion Tunnel

## Overview

This implementation uses OCI Bastion Service to create secure port-forwarding sessions to the private Kubernetes API endpoint. This allows Terraform/Terragrunt to deploy cluster services while keeping the API endpoint private.

## Architecture

```
┌─────────────────┐
│  Terragrunt     │
│  (localhost)    │
└────────┬────────┘
         │
         │ Terraform providers use:
         │ https://127.0.0.1:6443
         │
         ▼
┌─────────────────┐
│  SSH Tunnel     │
│  (port 6443)    │
└────────┬────────┘
         │
         │ OCI Bastion Port-Forward
         │ Session (3hr TTL)
         │
         ▼
┌─────────────────┐     ┌──────────────────┐
│ Bastion Service │────▶│  K8s API Server  │
│  (Public)       │     │  (10.0.10.165)   │
└─────────────────┘     │  Private Subnet  │
                        └──────────────────┘
```

## How It Works

1. **Before Hook**: Terragrunt executes `oci-bastion-kube-tunnel.sh` before `apply/plan/destroy`
2. **Idempotency Check**: Script validates if tunnel already exists:
   - Port 6443 is listening locally
   - SSH tunnel process points to correct target
   - TCP connectivity test succeeds
   - TLS handshake confirms K8s API endpoint
3. **Reuse or Create**: If all checks pass, reuses existing tunnel; otherwise creates new session
4. **Bastion Session**: Creates port-forwarding session (only if needed)
5. **SSH Tunnel**: Establishes SSH tunnel: `localhost:6443` → `10.0.10.165:6443`
6. **Providers**: Terraform Kubernetes/Helm providers connect to `https://127.0.0.1:6443`
7. **Authentication**: OCI CLI exec auth (`oci ce cluster generate-token`) provides credentials

**Idempotency Benefits**:
- ✅ No duplicate bastion sessions created
- ✅ Faster reruns (skips session creation if tunnel works)
- ✅ Automatic recovery from stale tunnels
- ✅ Safe to run multiple times

## Configuration

### Environment Variables

Set in your shell or `.envrc`:

```bash
export TG_VAR_bastion_ocid="ocid1.bastion.oc1.il-jerusalem-1.amaaaaaa..."
```

Default bastion OCID is configured in `live/oci-staging/env.hcl`.

### Script Configuration

The `scripts/oci-bastion-kube-tunnel.sh` script accepts:

| Variable | Default | Description |
|----------|---------|-------------|
| `BASTION_OCID` | (required) | OCI Bastion OCID |
| `K8S_PRIVATE_ENDPOINT` | (required) | Private IP of K8s API (e.g., 10.0.10.165) |
| `K8S_PORT` | 6443 | Target K8s API port |
| `LOCAL_K8S_PORT` | 6443 | Local port for tunnel |
| `BASTION_TTL` | 10800 | Session TTL in seconds (3 hours) |
| `SSH_KEY_PATH` | `~/.ssh/oci_bastion_k8s` | SSH key for bastion |
| `OCI_CLI_PROFILE` | DEFAULT | OCI CLI profile |
| `OCI_REGION` | il-jerusalem-1 | OCI region |
| `CLUSTER_ID` | (required) | OKE cluster OCID for token generation |

### Auto-Generated Files

- `kubeconfig.bastion` - Kubeconfig pointing to localhost tunnel
- `~/.ssh/oci_bastion_k8s` - Ed25519 SSH keypair (auto-generated if missing)

## Usage

### Automatic (via Terragrunt)

```bash
cd live/oci-staging/cluster-services
terragrunt apply  # Hook automatically creates tunnel
```

### Manual

```bash
export BASTION_OCID="ocid1.bastion.oc1..."
export K8S_PRIVATE_ENDPOINT="10.0.10.165"
export CLUSTER_ID="ocid1.cluster.oc1..."
export OCI_REGION="il-jerusalem-1"

./scripts/oci-bastion-kube-tunnel.sh

# Use the tunnel
KUBECONFIG=./kubeconfig.bastion kubectl get nodes
```

## Troubleshooting

### Port Already in Use

```bash
# Check what's using port 6443
lsof -i :6443

# Kill existing tunnel
pkill -f 'ssh.*6443:10.0.10.165:6443'
```

### Tunnel Not Responding

```bash
# Test connectivity
timeout 2 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/6443"

# Check bastion sessions
oci bastion session list --bastion-id <bastion_ocid> --lifecycle-state ACTIVE
```

### Session Timeout

Bastion sessions expire after TTL (default 3 hours). If deployment takes longer:

1. Increase `BASTION_TTL` environment variable
2. Or re-run terragrunt (hook recreates tunnel)

### Authentication Errors

```bash
# Verify OCI CLI can generate tokens
oci ce cluster generate-token --cluster-id <cluster_id>

# Check OCI config
cat ~/.oci/config
```

## Security Considerations

### ✅ Advantages

1. **Private API**: Kubernetes API never exposed to internet
2. **Temporary Access**: Sessions expire automatically (TTL)
3. **Audit Trail**: All bastion sessions logged in OCI
4. **No VPN**: No need for VPN or persistent connections
5. **OCI IAM**: Uses OCI CLI credentials for authentication

### ⚠️ Limitations

1. **Session Duration**: Max TTL depends on bastion configuration (typically 3 hours)
2. **Manual Cleanup**: Tunnels persist until killed or session expires
3. **Port Conflicts**: Cannot run multiple tunnels on same local port
4. **SSH Required**: Requires SSH client and key management

## Cost

- **Bastion Service**: ~$1.50/month (always running)
- **Port-Forwarding Sessions**: FREE (included in bastion cost)
- **Data Transfer**: FREE (within same region)

## Alternative: Public API Access

If you prefer public API access (for ArgoCD, CI/CD, etc.), see [PUBLIC_API_SETUP.md](PUBLIC_API_SETUP.md).

Public API approach:
- ✅ Simpler (no tunnel needed)
- ✅ Better for GitOps (ArgoCD direct access)
- ✅ Better for CI/CD pipelines
- ⚠️ Requires IP whitelisting for security
- ⚠️ API exposed to internet (protected by TLS + OCI IAM)

## References

- [OCI Bastion Documentation](https://docs.oracle.com/en-us/iaas/Content/Bastion/home.htm)
- [OCI Bastion Port Forwarding](https://docs.oracle.com/en-us/iaas/Content/Bastion/Tasks/managingsessions.htm#port-forwarding)
- [OKE Private Clusters](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengaccessingclusterkubectl.htm)
