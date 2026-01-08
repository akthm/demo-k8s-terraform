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

# Configure local backend for development
locals {
  # Load environment variables
  region   = get_env("TG_VAR_region", "ap-south-1")
  owner    = get_env("TG_VAR_owner", "akthmd")
  app_name = get_env("TG_VAR_app_name", "portfolio-platform")
}

# Generate provider configuration
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.0"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }
}
EOF
}

# Configure retry settings
retryable_errors = [
  "(?s).*Failed to load state.*",
  "(?s).*Error installing provider.*",
  "(?s).*connection reset by peer.*",
  "(?s).*TLS handshake timeout.*",
]

# Configure maximum number of times to retry
retry_max_attempts = 3

# Configure the amount of time to sleep between retries
retry_sleep_interval_sec = 5
