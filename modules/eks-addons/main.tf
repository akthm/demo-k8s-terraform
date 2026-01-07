variable "cluster_name" { type = string }
variable "endpoint"     { type = string }
variable "ca_data"      { type = string }
variable "version"      { type = string }
variable "oidc_arn"     { type = string }

variable "environment" { type = string }
variable "aws_region"  { type = string }
variable "region"       { type = string }

variable "owner" {
  type        = string
  description = "Owner used for naming/labels."
}
variable "app_name" {
  type        = string
  description = "App name used for naming/labels."
}
variable "common_tags" {
  type        = map(string)
  description = "Tags to apply to AWS resources."
  default     = {}
}

locals {
  # Use explicit inputs for module logic; tags are for tagging only.
  owner    = var.owner
  app_name = var.app_name
  name_prefix = "${local.owner}-${local.app_name}"
}

module "ebs_csi_irsa_role" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "5.30.0"
  role_name             = "${local.name_prefix}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = var.oidc_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0"

  cluster_name      = var.cluster_name
  cluster_endpoint  = var.endpoint
  cluster_version   = var.version
  oidc_provider_arn = var.oidc_arn

  eks_addons = {
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
    }
    coredns    = { most_recent = true }
    vpc-cni    = { most_recent = true }
    kube-proxy = { most_recent = true }
  }

  enable_external_secrets = true
  external_secrets = {
    service_account_name = "external-secrets-sa"
  }

  # IMPORTANT: this is EKS-only (IRSA). local-dev will not use this module.
  external_secrets_secrets_manager_arns = [
    "arn:aws:secretsmanager:${var.region}:*:secret:staging/backend/*"
  ]
  external_secrets_kms_key_arns = [
    "arn:aws:kms:${var.region}:*:key/*"
  ]
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

module "ebs_csi_storageclass" {
  source                 = "../ebs-csi-storageclass"
  host                   = var.endpoint
  cluster_ca_certificate = base64decode(var.ca_data)
  token                  = data.aws_eks_cluster_auth.this.token
}
