/**
 * ==============================================================================
 * Root Terraform Configuration & Providers
 * ==============================================================================
 * 
 * This file defines:
 *   - Required Terraform version
 *   - Required providers and versions
 *   - Remote state backend configuration
 *   - Shared provider defaults
 * 
 * IMPORTANT: AWS provider is defined here, but Kubernetes and Helm providers
 * are defined in the cluster_services module (they need EKS outputs).
 * ==============================================================================
 */


terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }


  # =========================================================================
  # Remote State Backend
  # =========================================================================
  # Uncomment and configure for production use.
  # Using S3 + DynamoDB for state locking is AWS best practice.
  # 
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"  # REQUIRED: Change this
  #   key            = "infrastructure/terraform.tfstate"
  #   region         = "ap-south-1"  # REQUIRED: Match your primary region
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
  #
  # To initialize the backend:
  #   terraform init -backend-config="bucket=your-bucket" -backend-config="key=infrastructure/terraform.tfstate" -backend-config="region=ap-south-1"
}

# ===============================================================================
# AWS Provider - Primary
# ===============================================================================
# This provider manages all AWS resources (VPC, EKS, IAM, etc.)

provider "aws" {
  region = var.region

  # Apply common tags to ALL resources created by the AWS provider
  # This ensures consistent tagging across the infrastructure
  default_tags {
    tags = var.common_tags
  }
}
