# OCI Staging - Cluster Services Module
# ArgoCD, NGINX Ingress Controller, cert-manager

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path   = "../env.hcl"
  expose = true
}

locals {

  bastion_ssh_key_path = include.env.locals.bastion_ssh_key_path
}

dependency "cluster" {
  config_path = "../cluster"

  mock_outputs = {
    cluster_id               = "ocid1.cluster.oc1.mock"
    cluster_name             = "oke-staging"
    cluster_endpoint         = "https://127.0.0.1:6443"  # Use localhost for tunnel
    cluster_public_endpoint  = "https://127.0.0.1:6443"  # Use localhost for tunnel
    cluster_ca_certificate   = "-----BEGIN CERTIFICATE-----\nMIICyDCCAbACCQD0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmno\npqrstuvwxyz0123456789+/ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/ABCD\nEFGHIJKLMNOPQRSTUVWXYZ0123456789+/ABCDEFGHIJKLMNOPQRSTUVWXYZ0123\n-----END CERTIFICATE-----"
    kubeconfig               = base64encode("mock-kubeconfig-yaml")
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "nodepool" {
  config_path = "../nodepool"

  mock_outputs = {
    node_pool_id = "ocid1.nodepool.oc1.mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "vault" {
  config_path = "../vault"

  mock_outputs = {
    vault_id  = "ocid1.vault.oc1.mock"
    region    = "il-jerusalem-1"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

# Terraform configuration with bastion tunnel before_hook
terraform {
  source = "${get_repo_root()}/modules/cluster_services"
  
  before_hook "bastion_tunnel" {
    commands = ["apply", "plan", "destroy"]
    execute  = [
      "${get_repo_root()}/scripts/oci-bastion-kube-tunnel.sh"
    ]
  }
  
  extra_arguments "env_vars" {
    commands = ["apply", "plan", "destroy", "refresh", "import"]
    
    env_vars = {
      BASTION_OCID        = "${include.env.locals.bastion_ocid}"
      K8S_PRIVATE_ENDPOINT = "10.0.10.165"
      K8S_PORT            = "6443"
      LOCAL_K8S_PORT      = "6443"
      SSH_KEY_PATH       = "${include.env.locals.bastion_ssh_key_path}"
      CLUSTER_ID          = "${dependency.cluster.outputs.cluster_id}"
      OCI_REGION          = "${include.env.locals.region}"
      KUBECONFIG_OUT      = "${get_terragrunt_dir()}/kubeconfig.bastion"
      KUBECONFIG          = "${get_terragrunt_dir()}/kubeconfig.bastion"
      VERBOSE             = "false" # Set to true for debugging
    }
  }
}

# Generate Kubernetes/Helm providers using localhost tunnel endpoint
generate "k8s_providers" {
  path      = "k8s_providers.tf"
  if_exists = "overwrite"
  contents  = <<-EOF
    provider "kubernetes" {
      host                   = "https://127.0.0.1:6443"
      cluster_ca_certificate = <<-CERT
${dependency.cluster.outputs.cluster_ca_certificate}
CERT
      exec {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "oci"
        args        = ["ce", "cluster", "generate-token", "--cluster-id", "${dependency.cluster.outputs.cluster_id}", "--region", "${include.env.locals.region}"]
      }
    }

    provider "helm" {
      kubernetes {
        host                   = "https://127.0.0.1:6443"
        cluster_ca_certificate = <<-CERT
${dependency.cluster.outputs.cluster_ca_certificate}
CERT
        exec {
          api_version = "client.authentication.k8s.io/v1beta1"
          command     = "oci"
          args        = ["ce", "cluster", "generate-token", "--cluster-id", "${dependency.cluster.outputs.cluster_id}", "--region", "${include.env.locals.region}"]
        }
      }
    }
  EOF
}

inputs = {
  # Platform selection - OKE
  platform = "oke"

  # Cluster info
  cluster_name                       = dependency.cluster.outputs.cluster_name
  cluster_endpoint                   = dependency.cluster.outputs.cluster_endpoint
  cluster_certificate_authority_data = "" # Provided via kubeconfig in provider

  # Environment
  environment = include.env.locals.environment
  owner       = include.env.locals.owner
  app_name    = include.env.locals.app_name

  # Services to deploy
  install_argocd           = true
  install_nginx_ingress    = true
  install_cert_manager     = true
  install_external_secrets = true # Enable External Secrets Operator for OCI Vault

  # NGINX Ingress - NodePort mode (for edge proxy)
  nginx_service_type   = "NodePort"
  nginx_http_nodeport  = 30080
  nginx_https_nodeport = 30443

  # ArgoCD configuration
  argocd_namespace       = "argocd"
  argocd_repo_url        = get_env("TG_VAR_argocd_repo_url", "https://github.com/example/argocd-apps.git")
  argocd_repo_path       = "apps/oci-staging"
  argocd_target_revision = "main"
  argocd_version         = "9.4.1" # The latest 
  
  # Git token for ArgoCD (from env var)
  git_token = get_env("TG_VAR_git_token", "")

  # cert-manager configuration
  cert_manager_email = get_env("TG_VAR_cert_manager_email", "admin@example.com")

  # OCI Vault configuration for External Secrets Operator
  oci_vault_id = try(dependency.vault.outputs.vault_id, "")
  oci_region   = include.env.locals.region

  # Cluster trigger for metrics-server
  cluster_trigger_id = dependency.cluster.outputs.cluster_id

  # Tags
  common_tags = {
    Environment = include.env.locals.environment
    ManagedBy   = "terragrunt"
    Owner       = include.env.locals.owner
    Application = include.env.locals.app_name
  }
}
