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

  after_hook "setup_localstack_secrets" {
    commands     = ["apply"]
    execute      = ["bash", "${get_repo_root()}/scripts/wait-and-setup-localstack.sh", "kind-local-dev", "localstack"]
    run_on_error = false
  }
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
    kubeconfig_path                    = "~/.kube/config"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

# Optional dependency on MetalLB - when enabled, nginx-ingress uses LoadBalancer
dependency "metallb" {
  config_path = "../metallb"
  
  # Skip this dependency if MetalLB module doesn't exist or isn't deployed
  skip_outputs = true
  
  mock_outputs = {
    ip_pool_range = ["172.18.255.200-172.18.255.250"]
    ip_pool_name  = "default"
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
  
  # MetalLB integration - enables LoadBalancer service type for nginx-ingress
  # Set to true after deploying MetalLB module: terragrunt apply --terragrunt-include-dir metallb
  use_metallb = tobool(get_env("TG_VAR_use_metallb", "false"))
  
  # nip.io domain for local development (e.g., platform.172.18.255.200.nip.io)
  # Set via environment variable after MetalLB assigns an IP to nginx-ingress
  # INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  # export TG_VAR_ingress_domain="platform.${INGRESS_IP}.nip.io"
  ingress_domain = get_env("TG_VAR_ingress_domain", "localhost")
  
  # Cluster configuration (from dependency)
  cluster_name                       = try(dependency.kind.outputs.cluster_name, "local-dev")
  cluster_endpoint                   = try(dependency.kind.outputs.cluster_endpoint, "https://127.0.0.1:6443")
  cluster_certificate_authority_data = try(dependency.kind.outputs.cluster_certificate_authority_data, "mock-ca-data")
  
  # ArgoCD configuration
  argocd_version         = "9.2.3"
  argocd_repo_url        = get_env("TG_VAR_argocd_repo_url", "https://github.com/akthm/demo-k8s-gitops")
  argocd_repo_path       = "apps/local"
  argocd_target_revision = get_env("TG_VAR_argocd_target_revision", "main")
  
  # Git token (should be provided via environment variable)
  git_token = get_env("TG_VAR_git_token", "")
}


