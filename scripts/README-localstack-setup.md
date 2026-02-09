# LocalStack Setup Script

## Overview

This script (`wait-and-setup-localstack.sh`) is executed automatically as an `after_hook` when running `terragrunt apply` on the local-dev cluster-services module.

## What It Does

1. **Waits for LocalStack namespace** to exist (up to 5 minutes)
2. **Waits for LocalStack pod** to be ready (up to 5 minutes)
3. **Cleans up** any existing port-forwards on port 4566
4. **Starts port-forward** from localhost:4566 to the LocalStack service
5. **Waits for LocalStack API** to respond (up to 60 seconds)
6. **Runs secrets setup script** (`scripts/subscripts/setupsecrets-localstack.sh`)
7. **Automatically cleans up** the port-forward when done

## Usage

### Automatic (via Terragrunt)

The script runs automatically after `terragrunt apply`:

```bash
cd live/local-dev/cluster-services
terragrunt apply
```

### Manual

You can also run it manually:

```bash
# From terraform root directory
./scripts/wait-and-setup-localstack.sh [context] [namespace]

# Examples:
./scripts/wait-and-setup-localstack.sh kind-local-dev localstack
./scripts/wait-and-setup-localstack.sh                          # Uses defaults
```

## Configuration

### Default Values

- **Kube Context**: `kind-local-dev` (first argument)
- **Namespace**: `localstack` (second argument)
- **Service Name**: `local-stack-localstack`
- **Local Port**: `4566`
- **Remote Port**: `4566`
- **Max Wait Time**: 300 seconds (5 minutes)

### Environment Variables for Secrets Script

The script automatically sets these for the secrets setup:

```bash
LOCALSTACK_ENDPOINT="http://localhost:4566"
AWS_ENDPOINT_URL="http://localhost:4566"
AWS_ACCESS_KEY_ID="test"
AWS_SECRET_ACCESS_KEY="test"
AWS_DEFAULT_REGION="us-east-1"
```

## Prerequisites

- kubectl configured with access to the cluster
- LocalStack deployed in the cluster (via ArgoCD or Helm)
- The secrets setup script at `scripts/subscripts/setupsecrets-localstack.sh`

## Troubleshooting

### Script fails immediately

Check if the namespace exists:
```bash
kubectl get namespace localstack --context kind-local-dev
```

### Port-forward fails

Check if port 4566 is already in use:
```bash
lsof -ti:4566
```

### LocalStack pod not ready

Check pod status:
```bash
kubectl get pods -n localstack --context kind-local-dev
kubectl logs -n localstack -l app=localstack --context kind-local-dev
```

### Secrets setup fails

Run the secrets script manually to see detailed output:
```bash
export LOCALSTACK_ENDPOINT="http://localhost:4566"
export AWS_ENDPOINT_URL="http://localhost:4566"
export AWS_ACCESS_KEY_ID="test"
export AWS_SECRET_ACCESS_KEY="test"

# Start port-forward in another terminal
kubectl port-forward -n localstack svc/localstack 4566:4566 --context kind-local-dev

# Run setup script
./scripts/subscripts/setupsecrets-localstack.sh
```

## Integration with Terragrunt

The after_hook is configured in `live/local-dev/cluster-services/terragrunt.hcl`:

```hcl
terraform {
  source = "../../../modules/cluster_services"

  after_hook "setup_localstack_secrets" {
    commands     = ["apply"]
    execute      = ["bash", "${get_repo_root()}/scripts/wait-and-setup-localstack.sh", "kind-local-dev", "localstack"]
    run_on_error = false
  }
}
```

## Files

- **Main Script**: `scripts/wait-and-setup-localstack.sh`
- **Secrets Setup**: `scripts/subscripts/setupsecrets-localstack.sh`
- **Terragrunt Config**: `live/local-dev/cluster-services/terragrunt.hcl`
