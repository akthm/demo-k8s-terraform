# Local development environment configuration
# This file is included by all terragrunt.hcl files in subdirectories

# Environment-specific variables
locals {
  environment = "local-dev"
  region      = get_env("TG_VAR_region", "ap-south-1")
  owner       = get_env("TG_VAR_owner", "akthmd")
  app_name    = get_env("TG_VAR_app_name", "portfolio-platform")
}

# Inputs that are common across all modules in this environment
inputs = {
  environment = local.environment
  owner       = local.owner
  app_name    = local.app_name
}
