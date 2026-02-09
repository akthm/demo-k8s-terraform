# Metrics Server Module

Platform-aware Kubernetes Metrics Server installation module. Automatically applies platform-specific configuration for Kind (insecure TLS), OKE, and EKS.

## Features

- **Platform-aware**: Automatic configuration based on target platform
- **Kind support**: Applies `--kubelet-insecure-tls` patch for self-signed certificates
- **OKE/EKS support**: Production-ready secure configuration
- **Dual installation**: Helm chart or raw manifest
- **Health checks**: Verifies `/apis/metrics.k8s.io/v1beta1` API availability

## Usage

### With Helm (Recommended)

```hcl
module "metrics_server" {
  source = "../../modules/metrics-server"

  platform     = "oke"
  cluster_name = "oke-staging"
  use_helm     = true
  helm_version = "3.12.0"
}
```

### With Manifest (Kind)

```hcl
module "metrics_server" {
  source = "../../modules/metrics-server"

  platform           = "kind"
  cluster_name       = "local-dev"
  use_helm           = false
  cluster_trigger_id = module.kind_cluster.cluster_id
}
```

### Integration with cluster-services

```hcl
module "metrics_server" {
  source = "../metrics-server"

  platform           = var.platform
  cluster_name       = var.cluster_name
  use_helm           = var.platform != "kind" # Helm for OKE/EKS, manifest for Kind
  cluster_trigger_id = var.cluster_trigger_id
}
```

## Platform Behavior

| Platform | Method | TLS Configuration | Notes |
|----------|--------|-------------------|-------|
| **kind** | Manifest | `--kubelet-insecure-tls` | Required for self-signed certs |
| **oke** | Helm | Secure (default) | Production-ready |
| **eks** | Helm | Secure (default) | EKS may have built-in metrics |

## Why Kind Needs Special Handling

Kind clusters use self-signed kubelet certificates. The metrics-server can't verify these certificates by default, causing connection failures:

```
unable to fetch pod metrics: x509: certificate signed by unknown authority
```

**Solution**: Add `--kubelet-insecure-tls` flag to skip certificate verification (local dev only).

## Verification

After deployment, verify metrics API:

```bash
# Check metrics API
kubectl get --raw /apis/metrics.k8s.io/v1beta1

# Get node metrics
kubectl top nodes

# Get pod metrics
kubectl top pods -A
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| platform | Platform (kind/oke/eks) | string | - | yes |
| cluster_name | Cluster name | string | - | yes |
| kube_context | Kubernetes context | string | auto | no |
| namespace | Namespace | string | kube-system | no |
| use_helm | Use Helm installation | bool | false | no |
| helm_version | Helm chart version | string | 3.12.0 | no |
| cluster_trigger_id | Cluster resource ID | string | "" | no |

## Outputs

| Name | Description |
|------|-------------|
| metrics_server_deployed | Deployment success status |
| deployment_method | Installation method (helm/manifest) |
| platform | Target platform |

## Dependencies

- `kubectl` CLI tool
- Kubernetes context configured
- For Helm: Helm provider configured

## Resource Requirements

- CPU: 100m request, 200m limit
- Memory: 200Mi request, 400Mi limit
- Namespace: kube-system (pre-existing)
