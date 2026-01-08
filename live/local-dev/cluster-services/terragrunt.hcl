# Terragrunt configuration for Cluster Services module

# Include the root configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Include environment configuration
include "env" {
  path = "../env.hcl"
  expose = true
}

# Configure the Terraform module source
terraform {
  source = "../../../modules/cluster_services"
}

# Generate provider configuration for Kubernetes and Helm
generate "provider_override" {
  path      = "provider_override.tf"
  if_exists = "overwrite"
  contents  = <<-EOF
    provider "kubernetes" {
      config_path = "~/.kube/config"
      config_context = "kind-${dependency.kind.outputs.cluster_name}"
    }
    
    provider "helm" {
      kubernetes {
        config_path = "~/.kube/config"
        config_context = "kind-${dependency.kind.outputs.cluster_name}"
      }
    }
  EOF
}

# Dependency on KIND cluster - cluster-services needs the cluster to exist first
dependency "kind" {
  config_path = "../kind"
  
  # Mock outputs for plan/validate when dependency doesn't exist yet
  mock_outputs = {
    cluster_name                       = "local-dev"
    cluster_endpoint                   = "https://127.0.0.1:6443"
    cluster_certificate_authority_data = "mock-ca-data"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

# Module-specific inputs
inputs = {
  # Basic configuration
  environment = "local-dev"
  owner       = get_env("TG_VAR_owner", "akthmd")
  app_name    = get_env("TG_VAR_app_name", "portfolio-platform")
  
  common_tags = {
    Environment = "local-dev"
    ManagedBy   = "terragrunt"
    Platform    = "kind"
    Owner       = get_env("TG_VAR_owner", "akthmd")
  }
  
  # Platform configuration
  platform = "kind"
  
  # Cluster configuration (from dependency)
  cluster_name                       = try(dependency.kind.outputs.cluster_name, "local-dev")
  cluster_endpoint                   = try(dependency.kind.outputs.cluster_endpoint, "https://127.0.0.1:6443")
  cluster_certificate_authority_data = try(dependency.kind.outputs.cluster_certificate_authority_data, "mock-ca-data")
  
  # ArgoCD configuration
  argocd_version         = "6.0.0"
  argocd_repo_url        = get_env("TG_VAR_argocd_repo_url", "https://github.com/akthm/demo-k8s-gitops")
  argocd_repo_path       = get_env("TG_VAR_argocd_repo_path", "apps/staging")
  argocd_target_revision = get_env("TG_VAR_argocd_target_revision", "main")
  
  # Git token (should be provided via environment variable)
  git_token = get_env("TG_VAR_git_token", "")
}
# End of terragrunt.hcl for Cluster Services module
