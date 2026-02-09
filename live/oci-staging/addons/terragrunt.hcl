# OCI Staging - Addons Module
# Storage classes and OCI-specific Kubernetes resources

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path   = "../env.hcl"
  expose = true
}

dependency "cluster" {
  config_path = "../cluster"

  mock_outputs = {
    cluster_id               = "ocid1.cluster.oc1.mock"
    cluster_endpoint         = "https://mock-endpoint:6443"
    cluster_public_endpoint  = "https://mock-endpoint:6443"
    cluster_ca_certificate   = "-----BEGIN CERTIFICATE-----\nMIICyDCCAbACCQD0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmno\npqrstuvwxyz0123456789+/ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/ABCD\nEFGHIJKLMNOPQRSTUVWXYZ0123456789+/ABCDEFGHIJKLMNOPQRSTUVWXYZ0123\n-----END CERTIFICATE-----"
    kubeconfig               = base64encode("mock-kubeconfig-yaml")
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

terraform {
  source = "${get_repo_root()}/modules/oci-block-storageclass"
}

# Generate Kubernetes provider using cluster kubeconfig
generate "kubernetes_provider" {
  path      = "kubernetes_provider.tf"
  if_exists = "overwrite"
  contents  = <<-EOF
    provider "kubernetes" {
      host                   = "${dependency.cluster.outputs.cluster_public_endpoint}"
      cluster_ca_certificate = <<-CERT
${dependency.cluster.outputs.cluster_ca_certificate}
CERT
      exec {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "oci"
        args        = ["ce", "cluster", "generate-token", "--cluster-id", "${dependency.cluster.outputs.cluster_id}", "--region", "${include.env.locals.region}"]
      }
    }
  EOF
}

inputs = {
  # Storage class configuration
  storage_class_name = "oci-bv"
  is_default         = true

  # Performance tier (10 = Balanced, stays within free tier)
  vpus_per_gb = 10

  # Attachment
  attachment_type = "paravirtualized"

  # Policies
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"
  allow_expansion     = true

  # Additional storage classes (optional)
  create_high_perf_class = false
  create_balanced_class  = false

  # Labels
  labels = {
    "app.kubernetes.io/managed-by" = "terragrunt"
    "environment"                  = "oci-staging"
  }
}
