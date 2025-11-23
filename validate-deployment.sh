#!/bin/bash

# Terraform + ArgoCD Pre-Deployment Validation Script
# This script checks all prerequisites before running terraform apply

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# Function to print section headers
section() {
    echo -e "\n${BLUE}==== $1 ====${NC}\n"
}

# Function to print success
success() {
    echo -e "${GREEN}✓${NC} $1"
    ((CHECKS_PASSED++))
}

# Function to print failure
failure() {
    echo -e "${RED}✗${NC} $1"
    ((CHECKS_FAILED++))
}

# Function to print warning
warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((CHECKS_WARNING++))
}

# === SECTION 1: System Prerequisites ===
section "System Prerequisites"

# Check Terraform
if command -v terraform &> /dev/null; then
    TF_VERSION=$(terraform version | head -n 1)
    success "Terraform installed: $TF_VERSION"
else
    failure "Terraform not installed"
fi

# Check kubectl
if command -v kubectl &> /dev/null; then
    KB_VERSION=$(kubectl version --client --short 2>/dev/null | head -n 1)
    success "kubectl installed: $KB_VERSION"
else
    failure "kubectl not installed"
fi

# Check AWS CLI
if command -v aws &> /dev/null; then
    AWS_VERSION=$(aws --version)
    success "AWS CLI installed: $AWS_VERSION"
else
    failure "AWS CLI not installed"
fi

# Check Git
if command -v git &> /dev/null; then
    GIT_VERSION=$(git --version)
    success "Git installed: $GIT_VERSION"
else
    failure "Git not installed"
fi

# === SECTION 2: AWS Credentials ===
section "AWS Credentials & Permissions"

# Check AWS credentials
if aws sts get-caller-identity &> /dev/null; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
    success "AWS credentials configured"
    echo "  Account ID: $ACCOUNT_ID"
    echo "  User/Role: $USER_ARN"
else
    failure "AWS credentials not configured or invalid"
fi

# Check required AWS permissions (these are IAM actions that should succeed if user has permissions)
echo ""
echo "Checking AWS permissions..."

# Check EKS permission (describe)
if aws eks list-clusters --region ap-south-1 &> /dev/null; then
    success "EKS permissions verified"
else
    warning "EKS permissions may be restricted"
fi

# Check EC2 permission
if aws ec2 describe-instances --region ap-south-1 --max-results 1 &> /dev/null; then
    success "EC2 permissions verified"
else
    warning "EC2 permissions may be restricted"
fi

# Check IAM permission
if aws iam get-account-summary &> /dev/null; then
    success "IAM permissions verified"
else
    warning "IAM permissions may be restricted"
fi

# === SECTION 3: Terraform Configuration ===
section "Terraform Configuration"

# Check if terraform files exist
if [ -f "terraform.tfvars" ]; then
    success "terraform.tfvars exists"
else
    failure "terraform.tfvars not found (required)"
fi

if [ -f "main.tf" ]; then
    success "main.tf exists"
else
    failure "main.tf not found"
fi

if [ -f "providers.tf" ]; then
    success "providers.tf exists"
else
    failure "providers.tf not found"
fi

if [ -f "variables.tf" ]; then
    success "variables.tf exists"
else
    failure "variables.tf not found"
fi

# Check if modules exist
if [ -d "modules/eks" ]; then
    success "EKS module exists"
else
    failure "EKS module not found"
fi

if [ -d "modules/cluster_services" ]; then
    success "cluster_services module exists"
else
    failure "cluster_services module not found"
fi

# Terraform validation
echo ""
echo "Running terraform validate..."
if terraform validate &> /dev/null; then
    success "Terraform configuration is valid"
else
    failure "Terraform validation failed (run: terraform validate)"
fi

# === SECTION 4: Required Variables ===
section "Required Variables Configuration"

# Function to check variable in tfvars
check_variable() {
    local var_name=$1
    local var_desc=$2
    
    if grep -q "^${var_name}" terraform.tfvars; then
        local var_value=$(grep "^${var_name}" terraform.tfvars | cut -d'=' -f2 | xargs)
        if [ -z "$var_value" ] || [ "$var_value" = '""' ] || [ "$var_value" = "''" ]; then
            warning "Variable $var_name is empty"
        else
            success "$var_desc configured"
        fi
    else
        warning "Variable $var_name not found in terraform.tfvars"
    fi
}

check_variable "argocd_hostname" "ArgoCD hostname"
check_variable "argocd_app_of_apps_repo_url" "GitOps repository URL"
check_variable "letsencrypt_email" "Let's Encrypt email"

# Check for git_token via environment variable
echo ""
echo "Checking Git token (sensitive)..."
if [ -z "$TF_VAR_git_token" ]; then
    warning "TF_VAR_git_token not set in environment (required for deployment)"
    echo "  Set with: export TF_VAR_git_token=\"ghp_xxxx...\""
else
    success "Git token environment variable is set"
fi

# === SECTION 5: kubectl Cluster Access ===
section "kubectl Cluster Access"

# Check kubeconfig
if [ -f "$HOME/.kube/config" ]; then
    success "kubeconfig file exists"
else
    warning "kubeconfig not found at $HOME/.kube/config"
fi

# Try to connect to existing cluster
if kubectl cluster-info &> /dev/null; then
    CLUSTER_NAME=$(kubectl config current-context)
    success "Connected to cluster: $CLUSTER_NAME"
    
    # Get node count
    NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    echo "  Nodes: $NODE_COUNT"
    
    # Check if enough resources
    if [ "$NODE_COUNT" -lt 2 ]; then
        warning "Only $NODE_COUNT nodes detected (recommend at least 2 for HA)"
    fi
else
    warning "No existing kubectl connection (will be created by Terraform)"
fi

# === SECTION 6: Git Repository ===
section "Git Repository Configuration"

if grep -q "argocd_app_of_apps_repo_url" terraform.tfvars; then
    REPO_URL=$(grep "argocd_app_of_apps_repo_url" terraform.tfvars | cut -d'=' -f2 | xargs | tr -d '"')
    
    if [ -n "$REPO_URL" ] && [ "$REPO_URL" != "''" ]; then
        # Try to access the repository
        if git ls-remote "$REPO_URL" &> /dev/null; then
            success "Git repository is accessible: $REPO_URL"
        else
            warning "Cannot access Git repository: $REPO_URL (verify credentials)"
        fi
    fi
fi

# === SECTION 7: Docker/Container Runtime ===
section "Container Runtime"

if command -v docker &> /dev/null; then
    success "Docker installed"
    
    # Check if running
    if docker ps &> /dev/null; then
        success "Docker daemon is running"
    else
        warning "Docker daemon is not running"
    fi
else
    warning "Docker not installed (needed for local testing only, not required for deployment)"
fi

# === SECTION 8: Storage Backend ===
section "Terraform State Management"

if grep -q "backend" providers.tf 2>/dev/null; then
    success "Backend configuration found in providers.tf"
    
    if grep -q "s3" providers.tf 2>/dev/null; then
        BUCKET=$(grep -A5 "backend.*s3" providers.tf | grep bucket | head -1 | cut -d'"' -f2)
        success "S3 backend configured for bucket: $BUCKET"
        
        # Check if bucket exists
        if aws s3 ls "s3://$BUCKET" &> /dev/null; then
            success "S3 bucket is accessible"
        else
            warning "S3 bucket not accessible or doesn't exist: $BUCKET"
        fi
    fi
else
    warning "No backend configuration found (state will be stored locally)"
fi

# === SECTION 9: Domain & DNS ===
section "Domain & DNS Configuration"

if grep -q "argocd_hostname" terraform.tfvars; then
    HOSTNAME=$(grep "argocd_hostname" terraform.tfvars | cut -d'=' -f2 | xargs | tr -d '"')
    
    if [ -n "$HOSTNAME" ] && [ "$HOSTNAME" != "''" ] && [ "$HOSTNAME" != "argocd.yourdomain.com" ]; then
        success "ArgoCD hostname configured: $HOSTNAME"
        
        # Check if DNS resolves
        if host "$HOSTNAME" &> /dev/null; then
            success "DNS resolves for: $HOSTNAME"
        else
            warning "DNS does not resolve for: $HOSTNAME (will be needed after deployment)"
        fi
    else
        warning "ArgoCD hostname not configured or placeholder value used"
        echo "  Set in terraform.tfvars: argocd_hostname = \"argocd.yourdomain.com\""
    fi
fi

# === SUMMARY ===
section "Validation Summary"

TOTAL=$((CHECKS_PASSED + CHECKS_FAILED + CHECKS_WARNING))

echo "Results:"
echo -e "  ${GREEN}Passed:${NC}  $CHECKS_PASSED"
echo -e "  ${YELLOW}Warnings:${NC} $CHECKS_WARNING"
echo -e "  ${RED}Failed:${NC}  $CHECKS_FAILED"
echo -e "  ${BLUE}Total:${NC}   $TOTAL"

echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All critical checks passed!${NC}"
    echo ""
    echo "You can now run:"
    echo "  1. terraform plan -var-file=\"terraform.tfvars\""
    echo "  2. terraform apply -var-file=\"terraform.tfvars\""
    echo ""
    exit 0
else
    echo -e "${RED}✗ Some critical checks failed. Please resolve the issues above.${NC}"
    echo ""
    exit 1
fi
