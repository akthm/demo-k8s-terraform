include "eks_env" {
  path = find_in_parent_folders("eks/terragrunt.hcl")
}

dependency "core" {
  config_path = "../core"
}

terraform {
  source = "${get_repo_root()}/modules/eks-addons"
}

inputs = {
  aws_region   = include.eks_env.inputs.aws_region
  environment  = include.eks_env.inputs.environment
  owner        = include.eks_env.inputs.owner
  app_name     = include.eks_env.inputs.app_name
  common_tags  = include.eks_env.inputs.common_tags

  cluster_name = dependency.core.outputs.cluster_name
  endpoint     = dependency.core.outputs.endpoint
  ca_data      = dependency.core.outputs.ca_data
  version      = dependency.core.outputs.version
  oidc_arn     = dependency.core.outputs.oidc_arn
}
