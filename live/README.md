# Terragrunt Live Configuration

This directory contains Terragrunt configurations for deploying infrastructure across different environments.

## Directory Structure

```
live/
└── local-dev/                    # Local development environment
    ├── terragrunt.hcl           # Environment-level configuration
    ├── env.hcl                  # Environment-specific variables
    ├── kind/                    # KIND cluster module
    │   └── terragrunt.hcl
    └── cluster-services/        # Cluster services (ArgoCD, etc.)
        └── terragrunt.hcl
```

## Usage

### Deploy Everything

Deploy all modules in dependency order:

```bash
# Source environment variables first
source ../../.env.terraform-backend

# Deploy all modules
cd live/local-dev
terragrunt run -all apply
```

### Deploy Individual Module

Deploy just the KIND cluster:

```bash
cd live/local-dev/kind
terragrunt apply
```

Deploy just the cluster services:

```bash
cd live/local-dev/cluster-services
terragrunt apply
```

### Destroy Everything

Destroy all resources in reverse dependency order:

```bash
cd live/local-dev
terragrunt run -all destroy
```

### Validate Configuration

```bash
cd live/local-dev
terragrunt run -all validate
```

### Plan All Changes

```bash
cd live/local-dev
terragrunt run -all plan
```

## Environment Variables

Set these environment variables before running Terragrunt:

```bash
# GitHub/GitLab token for ArgoCD private repo access
export TF_VAR_git_token="your-github-token"
```

## Dependencies

The modules are configured with proper dependencies:

1. **kind** - Creates the local Kubernetes cluster (no dependencies)
2. **cluster-services** - Deploys services to the cluster (depends on kind)

Terragrunt automatically handles dependency ordering during `run-all` operations.

## State Management

For local development, Terraform state is stored locally in each module directory under `.terraform/`.

For production environments, configure remote state in the root `terragrunt.hcl`.

## Troubleshooting

### Clear Terragrunt Cache

```bash
cd live/local-dev
find . -type d -name ".terragrunt-cache" -exec rm -rf {} + 2>/dev/null
```

### Reinitialize Terraform

```bash
cd live/local-dev/kind  # or cluster-services
rm -rf .terraform .terraform.lock.hcl
terragrunt init
```

### Check Dependency Graph

```bash
cd live/local-dev
terragrunt graph-dependencies
```
