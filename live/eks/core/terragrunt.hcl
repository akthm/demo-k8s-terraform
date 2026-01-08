include "eks_env" {
  path = find_in_parent_folders("eks/terragrunt.hcl")
}

terraform {
  source = "${get_repo_root()}/modules/eks-core"
}

inputs = {
  aws_region   = include.eks_env.inputs.aws_region
  environment  = include.eks_env.inputs.environment
  owner        = include.eks_env.inputs.owner
  app_name     = include.eks_env.inputs.app_name
  common_tags  = include.eks_env.inputs.common_tags

  # Keep existing EKS-specific inputs
  vpc_cidrs       = include.eks_env.inputs.vpc_cidrs
  ha              = include.eks_env.inputs.ha
  cluster_version = include.eks_env.inputs.cluster_version
  node_type       = include.eks_env.inputs.node_type
}
