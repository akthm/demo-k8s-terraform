# Terragrunt configuration for local-dev environment
# This file orchestrates the deployment of the entire local development stack

# Include the root configuration
include "root" {
  path = find_in_parent_folders()
}

# Local variables
locals {
  environment = "local-dev"
}

# Configure remote state (local backend for development)
terraform {
  # Use local backend for state management in development
  extra_arguments "auto_approve" {
    commands = [
      "apply",
      "destroy"
    ]
  }
}

# Common inputs for all modules in this environment
inputs = {
  environment = local.environment
}
