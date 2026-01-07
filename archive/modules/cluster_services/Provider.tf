/**
 * ==============================================================================
 * Cluster Services Module - Provider Configuration
 * ==============================================================================
 * 
 * This module receives provider configurations from the root module (main.tf)
 * instead of defining them locally. This allows the root module to manage
 * provider lifecycle and dependency ordering.
 * 
 * Providers are passed via the 'providers' argument in the module call.
 * ==============================================================================
 */

terraform {
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
  }
}