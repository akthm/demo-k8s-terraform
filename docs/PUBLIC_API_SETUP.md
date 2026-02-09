# OKE Public API Access Setup

## Overview

This guide explains how to make your OKE cluster API publicly accessible while maintaining security through IP whitelisting and OCI IAM authentication.

## When to Use Public API

Choose public API access if:

- ✅ Using GitOps (ArgoCD needs direct API access)
- ✅ CI/CD pipelines from external services (GitHub Actions, GitLab CI, etc.)
- ✅ Multiple developers need kubectl access without bastion
- ✅ Monitoring/observability tools need cluster access
- ✅ Prefer simpler configuration over bastion tunnels

## Security Model

Public API is secure when properly configured:

1. **TLS Certificate Authentication**: Cluster uses TLS certs (not exposed to internet)
2. **OCI IAM**: Authentication via `oci ce cluster generate-token` (instance principal or user credentials)
3. **IP Whitelisting**: Optional restriction to specific IPs/CIDR ranges
4. **Network Security List**: OCI firewall rules control access

## Configuration

### Option 1: Open to All IPs (Most Common)

Update `live/oci-staging/network/terragrunt.hcl`:

```hcl
inputs = {
  # ... other config ...
  
  # Allow all IPs to access K8s API
  k8s_api_allowed_cidrs = ["0.0.0.0/0"]
}
```

### Option 2: IP Whitelisting

Restrict to specific IPs or networks:

```hcl
inputs = {
  # ... other config ...
  
  # Allow only specific IPs/ranges
  k8s_api_allowed_cidrs = [
    "203.0.113.0/24",      # Office network
    "198.51.100.50/32",    # CI/CD runner
    "192.0.2.100/32",      # Your home IP
  ]
}
```

### Option 3: Environment Variable

Use environment variable for flexibility:

```bash
# In your shell or .envrc
export TG_VAR_k8s_api_cidrs="0.0.0.0/0"

# Or for multiple IPs (comma-separated)
export TG_VAR_k8s_api_cidrs="203.0.113.0/24,198.51.100.50/32"
```

Then in `network/terragrunt.hcl`:

```hcl
inputs = {
  k8s_api_allowed_cidrs = split(",", get_env("TG_VAR_k8s_api_cidrs", "10.0.0.0/16"))
}
```

## Deployment Steps

### 1. Update Network Configuration

```bash
cd live/oci-staging/network

# Edit terragrunt.hcl to set k8s_api_allowed_cidrs
vim terragrunt.hcl
```

### 2. Apply Network Changes

```bash
terragrunt apply
```

This updates the public subnet security list to allow ingress on TCP/6443 from configured CIDRs.

### 3. Update Kubeconfig

Get new kubeconfig with public endpoint:

```bash
cd live/oci-staging/cluster

# Regenerate outputs to get public endpoint
terragrunt output cluster_public_endpoint

# Update kubeconfig to use public endpoint
oci ce cluster create-kubeconfig \
  --cluster-id <cluster_ocid> \
  --file ~/.kube/config \
  --region il-jerusalem-1 \
  --token-version 2.0.0 \
  --kube-endpoint PUBLIC_ENDPOINT
```

### 4. Test Access

```bash
# Should work without bastion tunnel
kubectl get nodes

# Verify you're using public endpoint
kubectl config view --minify | grep server
# Should show: server: https://129.159.133.121:6443
```

### 5. Update Cluster Services

Remove bastion tunnel hook from `live/oci-staging/cluster-services/terragrunt.hcl`:

```hcl
# Comment out or remove the before_hook section
# terraform {
#   before_hook "bastion_tunnel" {
#     ...
#   }
# }
```

Update provider configuration to use public endpoint:

```hcl
generate "k8s_providers" {
  path      = "k8s_providers.tf"
  if_exists = "overwrite"
  contents  = <<-EOF
    provider "kubernetes" {
      host                   = "${dependency.cluster.outputs.cluster_public_endpoint}"
      cluster_ca_certificate = <<-CERT
${dependency.cluster.outputs.cluster_ca_certificate}
CERT
      exec {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "oci"
        args        = ["ce", "cluster", "generate-token", "--cluster-id", "${dependency.cluster.outputs.cluster_id}", "--region", "${include.env.locals.region}"]
      }
    }
    # ... helm provider similar ...
  EOF
}
```

### 6. Deploy Cluster Services

```bash
cd live/oci-staging/cluster-services
terragrunt apply
```

## Network Security List Changes

The network module creates this ingress rule:

```hcl
# modules/oci-network/main.tf
resource "oci_core_security_list" "public" {
  # ... other rules ...
  
  # Kubernetes API access from allowed CIDRs
  dynamic "ingress_security_rules" {
    for_each = var.k8s_api_allowed_cidrs
    content {
      source      = ingress_security_rules.value
      source_type = "CIDR_BLOCK"
      protocol    = "6" # TCP
      stateless   = false

      tcp_options {
        min = 6443
        max = 6443
      }
    }
  }
}
```

## Reverting to Private API

If you want to revert to private-only access:

### 1. Update Network

```hcl
# live/oci-staging/network/terragrunt.hcl
inputs = {
  k8s_api_allowed_cidrs = ["10.0.0.0/16"]  # VCN CIDR only
}
```

### 2. Apply Changes

```bash
cd live/oci-staging/network
terragrunt apply
```

### 3. Re-enable Bastion Tunnel

Restore the `before_hook` in cluster-services and update providers to use `https://127.0.0.1:6443`.

## Comparison: Public vs Private API

| Feature | Public API | Private API (Bastion) |
|---------|------------|----------------------|
| **Accessibility** | Direct from anywhere (with auth) | Requires bastion tunnel |
| **GitOps (ArgoCD)** | ✅ Works seamlessly | ❌ ArgoCD can't reach API |
| **CI/CD** | ✅ Easy integration | ⚠️ Requires runner in VCN or bastion |
| **Developer UX** | ✅ Simple kubectl access | ⚠️ Requires tunnel setup |
| **Security** | ⚠️ API exposed (TLS + IAM protect) | ✅ No internet exposure |
| **IP Whitelisting** | ✅ Available | N/A |
| **Audit Trail** | ✅ OCI API logs | ✅ Bastion session logs |
| **Maintenance** | ✅ No session management | ⚠️ 3hr session TTL |
| **Cost** | FREE | FREE (bastion already deployed) |

## Best Practices

### 1. Use IP Whitelisting

Even with public API, restrict access:

```hcl
k8s_api_allowed_cidrs = [
  "203.0.113.0/24",      # Office
  "198.51.100.0/24",     # CI/CD
]
```

### 2. Monitor Access

Enable OCI Audit logs for cluster API calls:

```bash
oci audit event list \
  --compartment-id <compartment_id> \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-31T23:59:59Z
```

### 3. Use RBAC

Kubernetes RBAC controls what authenticated users can do:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: read-only-users
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
- kind: User
  name: developer@example.com
```

### 4. Rotate Credentials

Regularly rotate OCI API keys and cluster certificates.

### 5. Enable Network Policies

Use Kubernetes NetworkPolicies to control pod-to-pod traffic.

## Troubleshooting

### Cannot Connect to Public Endpoint

```bash
# Test connectivity
curl -k https://129.159.133.121:6443

# Check security list rules
oci network security-list get --security-list-id <sl_ocid>

# Verify your IP is whitelisted
curl ifconfig.me  # Get your public IP
```

### Authentication Errors

```bash
# Verify OCI CLI works
oci ce cluster list --compartment-id <compartment_id>

# Test token generation
oci ce cluster generate-token --cluster-id <cluster_id>

# Check kubeconfig
kubectl config view --raw
```

### Firewall Blocking Access

Your corporate/home firewall may block port 6443:

```bash
# Test from different network
# Or use bastion tunnel as fallback
```

## Cost Impact

Making API public has **zero additional cost**:

- Security list rules: FREE
- Public IP (already allocated): FREE
- API traffic: FREE (within OCI)
- External API calls: FREE (OCI doesn't charge for this)

## References

- [OKE Security Best Practices](https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengaboutaccesscontrol.htm)
- [OCI Network Security Lists](https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/securitylists.htm)
- [Kubernetes Authentication](https://kubernetes.io/docs/reference/access-authn-authz/authentication/)
