# OCI Staging - Vault Module
# Creates OCI Vault, encryption keys, and IAM policies for OKE access

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
    cluster_id   = "ocid1.cluster.oc1.mock"
    cluster_name = "oke-staging"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "wallet_bucket" {
  config_path = "../wallet-bucket"
  
  mock_outputs = {
    bucket_name      = "oke-staging-atp-wallets"
    bucket_namespace = "mock-namespace"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

terraform {
  source = "${get_repo_root()}/modules/oci-vault"
}

# Generate OCI provider configuration
generate "oci_provider" {
  path      = "oci_provider.tf"
  if_exists = "overwrite"
  contents  = <<-EOF
    provider "oci" {
      tenancy_ocid         = "${include.env.locals.tenancy_ocid}"
      user_ocid            = "${include.env.locals.user_ocid}"
      fingerprint          = "${include.env.locals.fingerprint}"
      private_key_path     = "${include.env.locals.private_key_path}"
      private_key_password = "${include.env.locals.private_key_password}"
      region               = "${include.env.locals.region}"
    }
  EOF
}

inputs = {
  compartment_id = include.env.locals.compartment_id
  tenancy_ocid   = include.env.locals.tenancy_ocid
  vault_name     = "${include.env.locals.cluster_name}-vault"
  cluster_name   = include.env.locals.cluster_name
  cluster_id     = dependency.cluster.outputs.cluster_id
  vault_type     = "DEFAULT"
  region         = include.env.locals.region
  
  # Create dynamic group and IAM policy for OKE instance principal auth
  create_dynamic_group = true
  create_iam_policy    = true
  
  # Wallet bucket configuration (conditional - only if wallet-bucket module exists)
  wallet_bucket_name      = try(dependency.wallet_bucket.outputs.bucket_name, "")
  wallet_object_name      = "stagingdb_wallet.zip"
  wallet_bucket_namespace = try(dependency.wallet_bucket.outputs.bucket_namespace, "")
  
  # Application secrets (one JSON blob per application)
  # NOTE: These are placeholder values - update with real secrets after provisioning
  application_secrets = {
    "flask-app" = {
      description = "Flask application secrets and database credentials"
      data = {
        SECRET_KEY                 = "change-me-to-random-key"
        API_TEST_KEY               = "change-me-to-test-key"
        DB_USER                    = "flask_user"
        DB_PASSWORD                = "change-me-to-secure-password"
        DB_HOST                    = "" # Will be updated after ATP creation
        DB_PORT                    = "1521"
        DB_NAME                    = "stagingdb_high"
        DATABASE_ENCRYPTION_KEY_V1 = "change-me-to-fernet-key"
        CURRENT_KEY_VERSION        = "v1"
        JWT_PRIVATE_KEY            = "" # RSA private key for JWT signing
        JWT_PUBLIC_KEY             = "" # RSA public key for JWT verification
        OIDC_CLIENT_ID             = "flask-backend"
        OIDC_CLIENT_SECRET         = "change-me-to-keycloak-secret"
      }
    }
    
    "keycloak" = {
      description = "Keycloak identity provider secrets"
      data = {
        admin_user     = "admin"
        admin_password = "change-me-to-admin-password"
        DB_USER        = "keycloak"
        DB_PASSWORD    = "change-me-to-secure-password"
        DB_HOST        = "" # Will be updated after ATP creation
        DB_PORT        = "1521"
        DB_NAME        = "stagingdb_high"
        flask_backend_secret = "change-me-to-backend-secret"
        grafana_secret       = "change-me-to-grafana-secret"
        argocd_secret        = "change-me-to-argocd-secret"
      }
    }
    
    "cloudflare" = {
      description = "Cloudflare API token for DNS01 challenge (Let's Encrypt)"
      data = {
        CLOUDFLARE_API_TOKEN = "change-me-to-cloudflare-token"
        CLOUDFLARE_EMAIL     = "admin@example.com"
        CLOUDFLARE_ZONE_ID   = "change-me-to-zone-id"
      }
    }
    
    "monitoring" = {
      description = "Grafana and Prometheus secrets"
      data = {
        GRAFANA_ADMIN_USER     = "admin"
        GRAFANA_ADMIN_PASSWORD = "change-me-to-admin-password"
        GRAFANA_OIDC_CLIENT_ID = "grafana"
        GRAFANA_OIDC_SECRET    = "change-me-to-oidc-secret"
      }
    }
  }
  
  tags = {
    Environment = include.env.locals.environment
    ManagedBy   = "terragrunt"
    Owner       = include.env.locals.owner
    Application = include.env.locals.app_name
  }
}
