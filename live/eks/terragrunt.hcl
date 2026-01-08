include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

locals {
  environment = "staging"

  common_tags = merge(
    include.root.locals.common_tags,
    {
      environment = local.environment
      stack       = "eks"
    }
  )
}

inputs = {
  aws_region  = include.root.locals.aws_region
  environment = local.environment

  owner       = include.root.locals.owner
  app_name    = include.root.locals.app_name
  common_tags = local.common_tags

  # EKS-specific defaults (override root inputs as needed)
  vpc_cidrs        = ["10.0.0.0/16"]
  ha              = true
  cluster_version  = "1.30"
  node_type        = "t3.medium"

  argocd_version         = "7.6.12"
  argocd_repo_url        = get_env("TG_VAR_argocd_repo_url", "")
  argocd_repo_path       = get_env("TG_VAR_argocd_repo_path", "gitops/root")
  argocd_target_revision = get_env("TG_VAR_argocd_target_revision", "main")
  
  # TODO(PAT/GitOps): do NOT pass PATs via Terraform/Terragrunt inputs.
  #                   Later we will add a SOPS/SealedSecrets-based GitOps secret strategy.
}
