#!/bin/bash
################################################################################
# LocalStack Secrets Manager Setup Script
# 
# This script creates all necessary AWS Secrets Manager secrets for local
# development using LocalStack.
#
# Usage:
#   ./setup-localstack-secrets.sh [options]
#
# Options:
#   -e, --env ENV          Environment name (default: local)
#   -r, --region REGION    AWS region (default: us-east-1)
#   -h, --host HOST        LocalStack host (default: localhost)
#   -p, --port PORT        LocalStack port (default: 4566)
#   --help                 Show this help message
################################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
ENV="${ENVIRONMENT:-staging}"
REGION="${AWS_REGION:-ap-south-1}"
LOCALSTACK_HOST="${LOCALSTACK_HOST:-localhost}"
LOCALSTACK_PORT="${LOCALSTACK_PORT:-4566}"
LOCALSTACK_ENDPOINT="http://${LOCALSTACK_HOST}:${LOCALSTACK_PORT}"

# Database defaults
DB_USER="${DB_USER:-flask_user}"
DB_PASSWORD="${DB_PASSWORD:-local_dev_password_123}"
DB_HOST="${DB_HOST:-flask-app-db.backend.svc.cluster.local}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-flask_staging}"
# Generate Fernet key for encryption (will be v1)
DB_ENCRYPTION_KEY_V1="${DB_E_K:-xur6piRwSYRAIiBUgIJE4F27GgGG-QLBXdHkdYGl7Io=}"

# Admin defaults
ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin123}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@localhost.com}"

# Keycloak defaults
KEYCLOAK_ADMIN_USER="${KEYCLOAK_ADMIN_USER:-admin}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-admin123}"
KEYCLOAK_POSTGRES_PASSWORD="${KEYCLOAK_POSTGRES_PASSWORD:-postgres123}"
KEYCLOAK_DB_PASSWORD="${KEYCLOAK_DB_PASSWORD:-keycloak123}"

# Keycloak client secrets (generate random for local)
KEYCLOAK_FLASK_SECRET="${KEYCLOAK_FLASK_SECRET:-flask-backend-secret-$(openssl rand -hex 16)}"
KEYCLOAK_GRAFANA_SECRET="${KEYCLOAK_GRAFANA_SECRET:-grafana-secret-$(openssl rand -hex 16)}"
KEYCLOAK_ARGOCD_SECRET="${KEYCLOAK_ARGOCD_SECRET:-argocd-secret-$(openssl rand -hex 16)}"

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

check_dependencies() {
    local missing=()
    
    if ! command -v aws &> /dev/null; then
        missing+=("aws-cli")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi
    
    if ! command -v openssl &> /dev/null; then
        missing+=("openssl")
    fi
    
    if ! command -v python3 &> /dev/null; then
        missing+=("python3")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing required dependencies: ${missing[*]}"
        echo ""
        echo "Please install them first:"
        echo "  - macOS: brew install awscli jq openssl python3"
        echo "  - Ubuntu/Debian: sudo apt-get install awscli jq openssl python3"
        echo "  - RHEL/CentOS: sudo yum install awscli jq openssl python3"
        exit 1
    fi
}

check_localstack() {
    print_info "Checking LocalStack availability at ${LOCALSTACK_ENDPOINT}..."
    
    if ! curl -s "${LOCALSTACK_ENDPOINT}/_localstack/health" > /dev/null 2>&1; then
        print_error "LocalStack is not running at ${LOCALSTACK_ENDPOINT}"
        echo ""
        echo "Start LocalStack with:"
        echo "  docker-compose up -d localstack"
        echo "  OR"
        echo "  localstack start"
        exit 1
    fi
    
    print_success "LocalStack is running"
}

aws_local() {
    # Set dummy credentials for LocalStack if not already set
    export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
    export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
    
    aws --endpoint-url="${LOCALSTACK_ENDPOINT}" \
        --region="${REGION}" \
        --no-verify-ssl \
        "$@" 2>&1
}

secret_exists() {
    local secret_name="$1"
    if aws_local secretsmanager describe-secret --secret-id "${secret_name}" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

delete_secret_if_exists() {
    local secret_name="$1"
    if secret_exists "${secret_name}"; then
        print_warning "Secret '${secret_name}' already exists. Deleting..."
        aws_local secretsmanager delete-secret \
            --secret-id "${secret_name}" \
            --force-delete-without-recovery > /dev/null 2>&1 || true
        sleep 1
    fi
}

################################################################################
# Secret Creation Functions
################################################################################

create_database_secret() {
    local secret_name="${ENV}/backend/database"
    
    print_header "Creating Database Credentials Secret"
    
    delete_secret_if_exists "${secret_name}"
    
    local rotation_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local secret_value=$(jq -n \
        --arg user "$DB_USER" \
        --arg pass "$DB_PASSWORD" \
        --arg host "$DB_HOST" \
        --arg port "$DB_PORT" \
        --arg name "$DB_NAME" \
        --arg enckey_v1 "$DB_ENCRYPTION_KEY_V1" \
        --arg rotation_date "$rotation_date" \
        '{
            DB_USER: $user,
            DB_PASSWORD: $pass,
            DB_HOST: $host,
            DB_PORT: $port,
            DB_NAME: $name,
            DATABASE_ENCRYPTION_KEY_V1: $enckey_v1,
            CURRENT_KEY_VERSION: "v1",
            ROTATION_DATE: $rotation_date
        }')
    
    aws_local secretsmanager create-secret \
        --name "${secret_name}" \
        --description "MySQL database credentials for Flask backend (${ENV})" \
        --secret-string "${secret_value}" > /dev/null
    
    print_success "Created secret: ${secret_name}"
    echo "    DB_USER: ${DB_USER}"
    echo "    DB_HOST: ${DB_HOST}"
    echo "    DB_NAME: ${DB_NAME}"
    echo "    Encryption key version: v1"
    echo "    Will be mounted at: /run/secrets/db_encryption_keys/v1.key"
}

create_flask_app_secret() {
    local secret_name="${ENV}/backend/flask-app"
    
    print_header "Creating Flask Application Secrets"
    
    delete_secret_if_exists "${secret_name}"
    
    print_info "Generating secure random keys..."
    local flask_secret=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    local api_test_key=$(python3 -c "import secrets; print(secrets.token_hex(16))")
    
    local secret_value=$(jq -n \
        --arg secret "$flask_secret" \
        --arg api "$api_test_key" \
        '{
            SECRET_KEY: $secret,
            API_TEST_KEY: $api
        }')
    
    aws_local secretsmanager create-secret \
        --name "${secret_name}" \
        --description "Flask application secrets (${ENV})" \
        --secret-string "${secret_value}" > /dev/null
    
    print_success "Created secret: ${secret_name}"
    echo "    SECRET_KEY: ${flask_secret:0:16}... (64 chars)"
    echo "    API_TEST_KEY: ${api_test_key:0:8}... (32 chars)"
}

create_admin_secret() {
    local secret_name="${ENV}/backend/admin"
    
    print_header "Creating Admin User Credentials"
    
    delete_secret_if_exists "${secret_name}"
    
    local secret_value=$(jq -n \
        --arg username "$ADMIN_USERNAME" \
        --arg password "$ADMIN_PASSWORD" \
        --arg email "$ADMIN_EMAIL" \
        '{
            INITIAL_ADMIN_USERNAME: $username,
            INITIAL_ADMIN_PASSWORD: $password,
            INITIAL_ADMIN_EMAIL: $email
        }' | jq -c .)
    
    
    aws_local secretsmanager create-secret \
        --name "${secret_name}" \
        --description "Initial admin user credentials (${ENV})" \
        --secret-string "${secret_value}" > /dev/null
    
    print_success "Created secret: ${secret_name}"
    echo "    Username: ${ADMIN_USERNAME}"
    echo "    Email: ${ADMIN_EMAIL}"
}

create_jwt_keys_secret() {
    local secret_name="${ENV}/backend/jwt-keys"
    
    print_header "Creating JWT RSA Key Pair (Multi-Version Support)"
    
    delete_secret_if_exists "${secret_name}"
    
    print_info "Generating 2048-bit RSA key pair with rotation support..."
    
    # Generate keys in temporary directory
    local temp_dir=$(mktemp -d)
    local private_key="${temp_dir}/private.pem"
    local public_key="${temp_dir}/public.pem"
    
    # Generate RSA keys
    openssl genrsa -out "${private_key}" 2048 2>/dev/null
    openssl rsa -in "${private_key}" -pubout -out "${public_key}" 2>/dev/null
    
    # Read keys
    local jwt_private=$(cat "${private_key}")
    local jwt_public=$(cat "${public_key}")
    
    # Create secret with rotation metadata
    # Initial setup: Only CURRENT keys, no PREVIOUS
    local rotation_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local secret_value=$(jq -n \
        --arg private "$jwt_private" \
        --arg public "$jwt_public" \
        --arg rotation_date "$rotation_date" \
        '{
            JWT_PRIVATE_KEY: $private,
            JWT_PUBLIC_KEY: $public,
            JWT_PRIVATE_KEY_PREVIOUS: "",
            JWT_PUBLIC_KEY_PREVIOUS: "",
            ROTATION_DATE: $rotation_date,
            ROTATION_VERSION: "v1",
            GRACE_PERIOD_DAYS: "7"
        }')
    
    aws_local secretsmanager create-secret \
        --name "${secret_name}" \
        --description "JWT RSA key pair for token signing (${ENV}) - Rotation-ready" \
        --secret-string "${secret_value}" > /dev/null
    
    # Clean up
    rm -rf "${temp_dir}"
    
    print_success "Created secret: ${secret_name}"
    echo "    RSA key size: 2048 bits"
    echo "    Private key (CURRENT): ✓"
    echo "    Public key (CURRENT): ✓"
    echo "    Private key (PREVIOUS): (empty - first setup)"
    echo "    Public key (PREVIOUS): (empty - first setup)"
    echo "    Rotation version: v1"
    echo "    Rotation date: ${rotation_date}"
    echo "    Grace period: 7 days"
    print_info "Secret is ready for rotation support"
}

create_keycloak_admin_secret() {
    local secret_name="${ENV}/keycloak/admin"
    
    print_header "Creating Keycloak Admin Credentials"
    
    delete_secret_if_exists "${secret_name}"
    
    local secret_value=$(jq -n \
        --arg user "$KEYCLOAK_ADMIN_USER" \
        --arg pass "$KEYCLOAK_ADMIN_PASSWORD" \
        '{
            "admin-user": $user,
            "admin-password": $pass
        }')
    
    aws_local secretsmanager create-secret \
        --name "${secret_name}" \
        --description "Keycloak admin user credentials (${ENV})" \
        --secret-string "${secret_value}" > /dev/null
    
    print_success "Created secret: ${secret_name}"
    echo "    Admin user: ${KEYCLOAK_ADMIN_USER}"
}

create_keycloak_postgres_secret() {
    local secret_name="${ENV}/keycloak/postgres"
    
    print_header "Creating Keycloak PostgreSQL Credentials"
    
    delete_secret_if_exists "${secret_name}"
    
    local secret_value=$(jq -n \
        --arg postgres_pass "$KEYCLOAK_POSTGRES_PASSWORD" \
        --arg keycloak_pass "$KEYCLOAK_DB_PASSWORD" \
        '{
            "postgres-password": $postgres_pass,
            "password": $keycloak_pass
        }')
    
    aws_local secretsmanager create-secret \
        --name "${secret_name}" \
        --description "Keycloak PostgreSQL database credentials (${ENV})" \
        --secret-string "${secret_value}" > /dev/null
    
    print_success "Created secret: ${secret_name}"
    echo "    PostgreSQL admin password: ****"
    echo "    Keycloak DB password: ****"
}

create_keycloak_clients_secret() {
    local secret_name="${ENV}/keycloak/clients"
    
    print_header "Creating Keycloak Client Secrets"
    
    delete_secret_if_exists "${secret_name}"
    
    print_info "Generating client secrets..."
    
    local secret_value=$(jq -n \
        --arg flask "$KEYCLOAK_FLASK_SECRET" \
        --arg grafana "$KEYCLOAK_GRAFANA_SECRET" \
        --arg argocd "$KEYCLOAK_ARGOCD_SECRET" \
        '{
            "flask-backend-secret": $flask,
            "grafana-secret": $grafana,
            "argocd-secret": $argocd
        }')
    
    aws_local secretsmanager create-secret \
        --name "${secret_name}" \
        --description "Keycloak OIDC client secrets (${ENV})" \
        --secret-string "${secret_value}" > /dev/null
    
    print_success "Created secret: ${secret_name}"
    echo "    flask-backend-secret: ${KEYCLOAK_FLASK_SECRET:0:16}..."
    echo "    grafana-secret: ${KEYCLOAK_GRAFANA_SECRET:0:16}..."
    echo "    argocd-secret: ${KEYCLOAK_ARGOCD_SECRET:0:16}..."
    print_warning "Note: Update these in Keycloak after creating clients"
}

create_flask_oidc_secret() {
    local secret_name="${ENV}/backend/oidc"
    
    print_header "Creating Flask OIDC Credentials"
    
    delete_secret_if_exists "${secret_name}"
    
    local secret_value=$(jq -n \
        --arg client_id "flask-backend" \
        --arg client_secret "$KEYCLOAK_FLASK_SECRET" \
        '{
            OIDC_CLIENT_ID: $client_id,
            OIDC_CLIENT_SECRET: $client_secret
        }')
    
    aws_local secretsmanager create-secret \
        --name "${secret_name}" \
        --description "Flask OIDC/Keycloak credentials (${ENV})" \
        --secret-string "${secret_value}" > /dev/null
    
    print_success "Created secret: ${secret_name}"
    echo "    Client ID: flask-backend"
    echo "    Client Secret: ${KEYCLOAK_FLASK_SECRET:0:16}..."
}

################################################################################
# Verification Functions
################################################################################

verify_secrets() {
    print_header "Verifying Created Secrets"
    
    local secrets=(
        "${ENV}/backend/database"
        "${ENV}/backend/flask-app"
        "${ENV}/backend/admin"
        "${ENV}/backend/jwt-keys"
        "${ENV}/backend/oidc"
        "${ENV}/keycloak/admin"
        "${ENV}/keycloak/postgres"
        "${ENV}/keycloak/clients"
    )
    
    local all_exist=true
    
    for secret in "${secrets[@]}"; do
        if secret_exists "${secret}"; then
            print_success "✓ ${secret}"
        else
            print_error "✗ ${secret}"
            all_exist=false
        fi
    done
    
    if [ "$all_exist" = true ]; then
        echo ""
        print_success "All secrets created successfully!"
    else
        echo ""
        print_error "Some secrets failed to create"
        return 1
    fi
}

list_secrets() {
    print_header "Listing All Secrets"
    
    echo ""
    aws_local secretsmanager list-secrets \
        --query "SecretList[?starts_with(Name, '${ENV}/')].{Name:Name,Description:Description}" \
        --output table
}

show_secret_details() {
    local secret_name="$1"
    
    print_info "Fetching details for: ${secret_name}"
    
    local secret_value=$(aws_local secretsmanager get-secret-value \
        --secret-id "${secret_name}" \
        --query 'SecretString' \
        --output text)
    
    echo "${secret_value}" | jq .
}

################################################################################
# Main Execution
################################################################################

show_usage() {
    cat << EOF
Usage: $0 [options]

Options:
    -e, --env ENV          Environment name (default: local)
    -r, --region REGION    AWS region (default: us-east-1)
    -h, --host HOST        LocalStack host (default: localhost)
    -p, --port PORT        LocalStack port (default: 4566)
    --db-user USER         Database username (default: flask_user)
    --db-pass PASS         Database password (default: local_dev_password_123)
    --db-host HOST         Database host (default: flask-app-db.backend.svc.cluster.local)
    --db-name NAME         Database name (default: flask_local)
    --admin-user USER      Admin username (default: admin)
    --admin-pass PASS      Admin password (default: admin123)
    --admin-email EMAIL    Admin email (default: admin@localhost.com)
    --kc-admin-user USER   Keycloak admin username (default: admin)
    --kc-admin-pass PASS   Keycloak admin password (default: admin123)
    --verify-only          Only verify existing secrets
    --list                 List all secrets
    --show SECRET          Show details of a specific secret
    --help                 Show this help message

Environment Variables:
    ENVIRONMENT           Same as --env
    AWS_REGION            Same as --region
    LOCALSTACK_HOST       Same as --host
    LOCALSTACK_PORT       Same as --port
    DB_USER, DB_PASSWORD, DB_HOST, DB_NAME
    ADMIN_USERNAME, ADMIN_PASSWORD, ADMIN_EMAIL

Examples:
    # Create secrets with defaults
    $0

    # Create secrets for staging environment
    $0 --env staging

    # Use custom LocalStack endpoint
    $0 --host localstack.example.com --port 4566

    # Custom database credentials
    $0 --db-user myuser --db-pass mypass --db-name mydb

    # Verify existing secrets
    $0 --verify-only

    # List all secrets
    $0 --list

    # Show specific secret
    $0 --show local/backend/database
EOF
}

main() {
    local verify_only=false
    local list_only=false
    local show_secret=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--env)
                ENV="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -h|--host)
                LOCALSTACK_HOST="$2"
                LOCALSTACK_ENDPOINT="http://${LOCALSTACK_HOST}:${LOCALSTACK_PORT}"
                shift 2
                ;;
            -p|--port)
                LOCALSTACK_PORT="$2"
                LOCALSTACK_ENDPOINT="http://${LOCALSTACK_HOST}:${LOCALSTACK_PORT}"
                shift 2
                ;;
            --db-user)
                DB_USER="$2"
                shift 2
                ;;
            --db-pass)
                DB_PASSWORD="$2"
                shift 2
                ;;
            --db-host)
                DB_HOST="$2"
                shift 2
                ;;
            --db-name)
                DB_NAME="$2"
                shift 2
                ;;
            --admin-user)
                ADMIN_USERNAME="$2"
                shift 2
                ;;
            --admin-pass)
                ADMIN_PASSWORD="$2"
                shift 2
                ;;
            --admin-email)
                ADMIN_EMAIL="$2"
                shift 2
                ;;
            --kc-admin-user)
                KEYCLOAK_ADMIN_USER="$2"
                shift 2
                ;;
            --kc-admin-pass)
                KEYCLOAK_ADMIN_PASSWORD="$2"
                shift 2
                ;;
            --verify-only)
                verify_only=true
                shift
                ;;
            --list)
                list_only=true
                shift
                ;;
            --show)
                show_secret="$2"
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo ""
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Show configuration
    echo ""
    print_header "LocalStack Secrets Manager Setup"
    echo ""
    echo "Configuration:"
    echo "  Environment:    ${ENV}"
    echo "  Region:         ${REGION}"
    echo "  Endpoint:       ${LOCALSTACK_ENDPOINT}"
    echo ""
    
    # Check dependencies
    check_dependencies
    
    # Check LocalStack
    check_localstack
    
    echo ""
    
    # Handle special modes
    if [ "$list_only" = true ]; then
        list_secrets
        exit 0
    fi
    
    if [ -n "$show_secret" ]; then
        show_secret_details "$show_secret"
        exit 0
    fi
    
    if [ "$verify_only" = true ]; then
        verify_secrets
        exit 0
    fi
    
    # Create all secrets
    create_database_secret
    echo ""
    
    create_flask_app_secret
    echo ""
    
    create_admin_secret
    echo ""
    
    create_jwt_keys_secret
    echo ""
    
    create_keycloak_admin_secret
    echo ""
    
    create_keycloak_postgres_secret
    echo ""
    
    create_keycloak_clients_secret
    echo ""
    
    create_flask_oidc_secret
    echo ""
    
    # Verify creation
    verify_secrets
    echo ""
    
    # Show summary
    print_header "Setup Complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Update your application configuration to use these secrets"
    echo "  2. Configure External Secrets Operator (if using Kubernetes)"
    echo "  3. Test secret access: $0 --show ${ENV}/backend/database"
    echo ""
    print_warning "Remember: These are LOCAL development secrets only!"
    echo ""
}

# Run main function
main "$@"
