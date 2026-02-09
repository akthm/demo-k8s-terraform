# Cluster Services Deployment with Bastion Tunnel

## Quick Start

Deploy cluster services (ArgoCD, NGINX, cert-manager, ESO) using bastion tunnel for private API access:

```bash
# 1. Ensure bastion OCID is set (already configured in env.hcl)
echo $TG_VAR_bastion_ocid  # or check live/oci-staging/env.hcl

# 2. Deploy cluster services
cd live/oci-staging/cluster-services
terragrunt apply
```

The before_hook will automatically:
1. Create bastion port-forwarding session
2. Establish SSH tunnel to private K8s API
3. Generate kubeconfig pointing to localhost:6443
4. Configure Terraform providers to use tunnel

## What Gets Deployed

### External Secrets Operator (ESO)
- Helm chart: `external-secrets/external-secrets` v0.9.11
- Namespace: `external-secrets`
- Oracle provider enabled for OCI Vault integration
- ClusterSecretStore: `oci-vault` with instance principal auth

### Metrics Server
- Deployed via Helm (on OKE)
- Provides Resource Metrics API
- Required for `kubectl top nodes/pods`
- HPA (Horizontal Pod Autoscaler) support

### ArgoCD *(Optional)*
- GitOps continuous deployment
- Namespace: `argocd`
- Syncs from configured git repository

### NGINX Ingress Controller *(Optional)*
- NodePort service (30080/30443)
- Routes traffic to backend services

### cert-manager *(Optional)*
- Automated TLS certificate management
- Let's Encrypt integration

## Bastion Tunnel Architecture

```
Terragrunt Local
       ↓
   [before_hook]
       ↓
oci-bastion-kube-tunnel.sh
       ↓
   Creates:
   - Bastion session (3hr TTL)
   - SSH tunnel (localhost:6443 → 10.0.10.165:6443)
   - kubeconfig.bastion
       ↓
Terraform Providers
  host: https://127.0.0.1:6443
       ↓
   SSH Tunnel
       ↓
  Bastion Service
       ↓
K8s API (Private)
  10.0.10.165:6443
```

## Prerequisites

- ✅ Vault deployed (`live/oci-staging/vault`)
- ✅ Bastion service active
- ✅ OCI CLI configured
- ✅ SSH tools installed (`ssh`, `ssh-keygen`)
- ✅ `jq` installed

## Environment Configuration

### Required Variables

Set in `live/oci-staging/env.hcl`:

```hcl
locals {
  bastion_ocid = "ocid1.bastion.oc1.il-jerusalem-1.amaaaaaa..."  # Your bastion OCID
}
```

### Optional Variables

```bash
# Custom bastion TTL (default: 10800 = 3 hours)
export BASTION_TTL="7200"

# Custom SSH key location (default: ~/.ssh/oci_bastion_k8s)
export SSH_KEY_PATH="~/.ssh/my_bastion_key"

# Custom local port (default: 6443)
export LOCAL_K8S_PORT="16443"
```

## Step-by-Step Deployment

### 1. Verify Dependencies

```bash
# Check vault deployed
cd live/oci-staging/vault
terragrunt output vault_id

# Check bastion exists
oci bastion bastion get --bastion-id <bastion_ocid>
```

### 2. Review Configuration

```bash
cd live/oci-staging/cluster-services

# Check what will be deployed
terragrunt plan
```

### 3. Deploy Services

```bash
terragrunt apply
```

**What happens**:
1. Before hook runs `oci-bastion-kube-tunnel.sh`
2. Script checks if tunnel already exists and is working (idempotent)
3. If tunnel valid: reuses it (fast path)
4. If tunnel invalid/missing: creates new bastion session and SSH tunnel
5. Terraform generates providers pointing to `localhost:6443`
6. Helm charts deployed via tunnel:
   - External Secrets Operator
   - Metrics Server
   - ArgoCD (if enabled)
   - NGINX (if enabled)
   - cert-manager (if enabled)

### 4. Verify Deployment

```bash
# Verify ESO deployed
kubectl get pods -n external-secrets

# Verify ClusterSecretStore created
kubectl get clustersecretstore oci-vault

# Verify metrics-server
kubectl top nodes

# Verify ArgoCD (if enabled)
kubectl get pods -n argocd
```

## Troubleshooting

### Error: "Port 6443 already in use"

Tunnel may already exist from previous run:

```bash
# Check what's using port 6443
lsof -i :6443

# Kill existing tunnel
pkill -f 'ssh.*6443:10.0.10.165:6443'

# Re-run
terragrunt apply
```

### Error: "Could not create bastion session"

Check bastion status:

```bash
# Verify bastion is active
oci bastion bastion get --bastion-id <bastion_ocid> | jq '.data."lifecycle-state"'

# Check existing sessions (max sessions limit)
oci bastion session list --bastion-id <bastion_ocid> --lifecycle-state ACTIVE

# Delete old sessions if needed
oci bastion session delete --session-id <session_ocid>
```

### Error: "Connection refused to localhost:6443"

Tunnel failed to establish:

```bash
# Check SSH tunnel processes
ps aux | grep ssh | grep 6443

# Test connectivity manually
timeout 2 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/6443"

# Check bastion session logs in OCI Console
```

### Error: "exec plugin: invalid apiVersion"

OCI CLI version mismatch:

```bash
# Update OCI CLI
curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh | bash

# Verify version
oci --version
```

### Helm Release Fails

Check if tunnel is still active:

```bash
# Test kubectl via tunnel
kubectl get nodes

# If fails, tunnel may have expired - rerun terragrunt
terragrunt apply
```

## Managing Bastion Sessions

### List Active Sessions

```bash
oci bastion session list \
  --bastion-id <bastion_ocid> \
  --lifecycle-state ACTIVE \
  --output table
```

### Get Session Details

```bash
oci bastion session get \
  --session-id <session_ocid> | jq .
```

### Terminate Session

```bash
# Via CLI
oci bastion session delete --session-id <session_ocid>

# Or kill local tunnel (session remains active until TTL)
pkill -f 'ssh.*6443:10.0.10.165:6443'
```

## Session Expiration

Bastion sessions expire after TTL (default 3 hours).

**If deployment takes longer than 3 hours**:

1. Increase TTL before running:
   ```bash
   export BASTION_TTL="14400"  # 4 hours
   terragrunt apply
   ```

2. Or split deployment:
   ```bash
   # Deploy ESO and metrics-server first
   terragrunt apply -target=helm_release.external_secrets
   
   # Then deploy rest (creates new tunnel)
   terragrunt apply
   ```

## Cleanup

### Remove Tunnel

```bash
# Kill SSH tunnel
pkill -f 'ssh.*6443:10.0.10.165:6443'

# Remove generated kubeconfig
rm -f kubeconfig.bastion
```

### Destroy Services

```bash
cd live/oci-staging/cluster-services
terragrunt destroy
```

## Alternative: Public API Access

If you prefer to make K8s API publicly accessible (better for GitOps), see [PUBLIC_API_SETUP.md](PUBLIC_API_SETUP.md).

**Comparison**:

| Feature | Bastion Tunnel (Current) | Public API |
|---------|--------------------------|------------|
| **Security** | ✅ Private API | ⚠️ Public (TLS + IAM) |
| **ArgoCD** | ❌ Cannot reach API | ✅ Works seamlessly |
| **CI/CD** | ⚠️ Complex setup | ✅ Easy integration |
| **Maintenance** | ⚠️ 3hr session TTL | ✅ No session mgmt |
| **Setup** | ⚠️ Requires script/hook | ✅ Simple config |

## Files Generated

| File | Location | Purpose | Gitignored |
|------|----------|---------|------------|
| `kubeconfig.bastion` | cluster-services/ | Kubeconfig for tunnel | ✅ |
| `k8s_providers.tf` | cluster-services/ | Terraform providers | ✅ |
| `~/.ssh/oci_bastion_k8s` | Home directory | SSH private key | ✅ |
| `~/.ssh/oci_bastion_k8s.pub` | Home directory | SSH public key | ✅ |

## Security Considerations

### ✅ Secure
- Private K8s API endpoint (not exposed to internet)
- TLS certificate authentication
- OCI IAM authentication (`oci ce cluster generate-token`)
- Temporary bastion sessions (auto-expire)
- Audit trail in OCI (all bastion access logged)

### ⚠️ Limitations
- SSH keys stored unencrypted (required for automation)
- Local tunnel can be accessed by any user on machine
- Session TTL limits long-running operations

### Best Practices
1. Use dedicated SSH keys (auto-generated by script)
2. Keep BASTION_TTL as short as possible
3. Clean up old sessions regularly
4. Monitor bastion access logs in OCI Console
5. Use RBAC to limit what authenticated users can do

## Cost

- **Bastion Service**: ~$1.50/month (already deployed)
- **Port-Forwarding Sessions**: FREE
- **SSH Tunnels**: FREE
- **Data Transfer**: FREE (same region)

**Total additional cost**: $0

## References

- [Bastion Tunnel Guide](BASTION_TUNNEL_GUIDE.md) - Detailed tunnel documentation
- [Public API Setup](PUBLIC_API_SETUP.md) - Alternative approach
- [OCI Bastion Documentation](https://docs.oracle.com/en-us/iaas/Content/Bastion/home.htm)
- [Terragrunt Hooks](https://terragrunt.gruntwork.io/docs/features/hooks/)

## Next Steps

After cluster services are deployed:

1. **Deploy ATP**: `cd ../atp && terragrunt apply`
2. **Update Vault Secrets**: Add ATP connection details
3. **Verify ESO Sync**: Check ExternalSecrets pull from vault
4. **Configure ArgoCD**: Add application repositories
5. **Deploy Applications**: Use ArgoCD or kubectl
