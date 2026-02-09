# OKE Private API Access - Quick Reference

## Deploy Cluster Services (Automatic Tunnel)

```bash
cd live/oci-staging/cluster-services
terragrunt apply  # Hook creates tunnel automatically
```

## Manual Tunnel Setup

```bash
export BASTION_OCID="ocid1.bastion.oc1.il-jerusalem-1.amaaaaaa3z7gytyacd3nflem7yf7hg4p4zm72w6ortmfztzrqkmlbgktpc6a"
export K8S_PRIVATE_ENDPOINT="10.0.10.165"
export CLUSTER_ID="<your-cluster-ocid>"
export OCI_REGION="il-jerusalem-1"

./scripts/oci-bastion-kube-tunnel.sh
```

## Check Tunnel Status

```bash
# Is port listening?
lsof -i :6443

# Test connectivity
timeout 2 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/6443"

# Use tunnel
KUBECONFIG=./kubeconfig.bastion kubectl get nodes
```

## Stop Tunnel

```bash
pkill -f 'ssh.*6443:10.0.10.165:6443'
```

## List Bastion Sessions

```bash
oci bastion session list \
  --bastion-id ocid1.bastion.oc1.il-jerusalem-1.amaaaaaa3z7gytyacd3nflem7yf7hg4p4zm72w6ortmfztzrqkmlbgktpc6a \
  --lifecycle-state ACTIVE
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Port 6443 in use | `pkill -f 'ssh.*6443'` |
| Tunnel not responding | Kill and re-run script |
| Session expired (3hr) | Re-run terragrunt apply |
| SSH key missing | Auto-generated at ~/.ssh/oci_bastion_k8s |
| OCI CLI error | Check `~/.oci/config` |

## Environment Variables

```bash
export BASTION_TTL="7200"           # Session duration (seconds)
export LOCAL_K8S_PORT="16443"       # Local tunnel port
export SSH_KEY_PATH="~/.ssh/custom" # Custom SSH key location
```

## Files Generated

- `kubeconfig.bastion` - Kubeconfig for tunnel
- `~/.ssh/oci_bastion_k8s*` - SSH keys (auto-generated)

## Documentation

- **[BASTION_TUNNEL_GUIDE.md](BASTION_TUNNEL_GUIDE.md)** - Complete guide
- **[CLUSTER_SERVICES_DEPLOYMENT.md](CLUSTER_SERVICES_DEPLOYMENT.md)** - Deployment walkthrough
- **[PUBLIC_API_SETUP.md](PUBLIC_API_SETUP.md)** - Public API alternative
- **[scripts/README.md](../scripts/README.md)** - Scripts reference

## Architecture

```
Terragrunt → localhost:6443 → SSH Tunnel → Bastion → 10.0.10.165:6443
```

## Security

- ✅ Private K8s API (not exposed to internet)
- ✅ OCI IAM + SSH key authentication
- ✅ Sessions auto-expire (3hr default)
- ✅ All access logged in OCI Audit

## Cost

**$0 additional** (bastion already deployed)
