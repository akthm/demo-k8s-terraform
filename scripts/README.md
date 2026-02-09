# OCI Infrastructure Scripts

This directory contains automation scripts for OCI infrastructure management.

## Scripts

### oci-bastion-kube-tunnel.sh

Creates OCI Bastion port-forwarding session to private Kubernetes API endpoint.

**Purpose**: Allows Terraform/Terragrunt to deploy cluster services while keeping K8s API private.

**Usage**:

```bash
# Automatic (via Terragrunt hook)
cd live/oci-staging/cluster-services
terragrunt apply  # Automatically creates tunnel

# Manual
export BASTION_OCID="ocid1.bastion.oc1..."
export K8S_PRIVATE_ENDPOINT="10.0.10.165"
export CLUSTER_ID="ocid1.cluster.oc1..."
export OCI_REGION="il-jerusalem-1"

./scripts/oci-bastion-kube-tunnel.sh
```

**Requirements**:
- `oci` CLI configured
- `jq`, `ssh`, `ssh-keygen`
- Bastion deployed and active

**Documentation**: See [BASTION_TUNNEL_GUIDE.md](../docs/BASTION_TUNNEL_GUIDE.md)

### wait-and-setup-localstack.sh

*(For local-dev environment only)*

Waits for LocalStack to be ready and configures S3, Secrets Manager.

## Environment Variables

Scripts use these environment variables:

| Variable | Default | Used By | Description |
|----------|---------|---------|-------------|
| `BASTION_OCID` | (required) | bastion-tunnel | OCI Bastion OCID |
| `K8S_PRIVATE_ENDPOINT` | (required) | bastion-tunnel | Private IP of K8s API |
| `CLUSTER_ID` | (required) | bastion-tunnel | OKE cluster OCID |
| `OCI_REGION` | il-jerusalem-1 | bastion-tunnel | OCI region |
| `LOCAL_K8S_PORT` | 6443 | bastion-tunnel | Local tunnel port |
| `BASTION_TTL` | 10800 | bastion-tunnel | Session TTL (seconds) |
| `SSH_KEY_PATH` | ~/.ssh/oci_bastion_k8s | bastion-tunnel | SSH key path |

## Generated Files

Scripts may generate these files:

| File | Purpose | Gitignored |
|------|---------|------------|
| `kubeconfig.bastion` | Kubeconfig for bastion tunnel | ✅ Yes |
| `~/.ssh/oci_bastion_k8s*` | SSH keys for bastion | ✅ Yes |

## Development

### Testing Scripts Locally

```bash
# Dry-run (check syntax)
bash -n scripts/oci-bastion-kube-tunnel.sh

# Test with debug output
bash -x scripts/oci-bastion-kube-tunnel.sh
```

### Adding New Scripts

1. Create script in this directory
2. Make executable: `chmod +x scripts/your-script.sh`
3. Add documentation to this README
4. Add usage examples in relevant guides
5. Consider adding to `.gitignore` if generates files

## Troubleshooting

### Script Permissions

```bash
# Make all scripts executable
chmod +x scripts/*.sh
```

### Path Issues

Scripts use these path resolution methods:

- `get_repo_root()` - Terragrunt function for workspace root
- `${BASH_SOURCE[0]}` - Script's own location
- Absolute paths from environment variables

### Debug Mode

Enable bash debug output:

```bash
# In terragrunt.hcl before_hook
execute = ["bash", "-x", "-c", "..."]

# Or manually
bash -x scripts/oci-bastion-kube-tunnel.sh
```

## Security Notes

### SSH Keys

- Keys are auto-generated if missing
- Use Ed25519 (modern, secure)
- No passphrase (required for automation)
- Stored in `~/.ssh/oci_bastion_k8s*`
- **Never commit keys to git**

### Credentials

Scripts use OCI CLI authentication:

```bash
# User principal (local development)
cat ~/.oci/config

# Instance principal (from OKE pods)
# No config file needed - uses instance metadata
```

### Session Management

Bastion sessions:
- Expire after TTL (default 3 hours)
- Logged in OCI Audit
- Can be listed/terminated via OCI Console or CLI

```bash
# List active sessions
oci bastion session list \
  --bastion-id <bastion_ocid> \
  --lifecycle-state ACTIVE

# Terminate session
oci bastion session delete --session-id <session_ocid>
```

## Integration with Terragrunt

### Before Hooks

Run script before terraform commands:

```hcl
terraform {
  before_hook "my_hook" {
    commands = ["apply", "plan"]
    execute  = ["bash", "${get_repo_root()}/scripts/my-script.sh"]
  }
}
```

### After Hooks

Run script after terraform commands:

```hcl
terraform {
  after_hook "cleanup" {
    commands     = ["apply", "destroy"]
    execute      = ["bash", "-c", "pkill -f 'ssh.*6443'"]
    run_on_error = true
  }
}
```

### Error Handling

Scripts should:
- Use `set -euo pipefail` for safety
- Exit with non-zero on errors
- Provide clear error messages
- Clean up resources on failure

## References

- [Terragrunt Hooks](https://terragrunt.gruntwork.io/docs/features/hooks/)
- [OCI CLI Reference](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/)
- [OCI Bastion](https://docs.oracle.com/en-us/iaas/Content/Bastion/home.htm)
