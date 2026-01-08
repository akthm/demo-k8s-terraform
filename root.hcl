# Root terragrunt configuration
# This file defines shared configuration for all terragrunt modules

# Configure Terragrunt to automatically store tfstate files in an S3 bucket
remote_state {
  backend = "s3"
  config = {
    bucket         = get_env("TG_STATE_BUCKET", "akthmd-portfolio-platform-terraform-backend-states")
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = get_env("TG_VAR_region", "ap-south-1")
    encrypt        = true
    dynamodb_table = get_env("TG_STATE_LOCK_TABLE", "akthmd-portfolio-platform-terraform-backend-locks")
    profile        = get_env("TG_VAR_profile", "personal-local-dev")
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }
}

# Note: Provider configuration is managed by individual modules
# (modules/kind-cluster and modules/cluster_services already have provider configs)
