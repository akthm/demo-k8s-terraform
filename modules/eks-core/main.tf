locals {
  # Use explicit inputs for module logic; tags are for tagging only.
  owner    = var.owner
  app_name = var.app_name
  name_prefix = "${local.owner}-${local.app_name}"
}

module "network" {
  source      = "../network"
  name_prefix = local.name_prefix
  vpc_cidrs   = var.vpc_cidrs
  ha          = var.ha
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 20.31"
  cluster_name    = "${var.common_tags.owner}-cluster"
  cluster_version = var.cluster_version
  subnet_ids      = module.network.subnet_ids
  vpc_id          = module.network.vpc_id

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    main = {
      name         = "${var.common_tags.owner}-eks-node"
      desired_size = 2
      max_size     = 2
      min_size     = 1
      instance_types = [var.node_type]
    }
  }
}

output "cluster_name"  { value = module.eks.cluster_name }
output "endpoint"      { value = module.eks.cluster_endpoint }
output "ca_data"       { value = module.eks.cluster_certificate_authority_data }
output "version"       { value = module.eks.cluster_version }
output "oidc_arn"      { value = module.eks.oidc_provider_arn }
