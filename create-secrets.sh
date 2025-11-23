#!/bin/bash
# ==============================================================================
# AWS Secrets Manager Setup for Flask Backend
# ==============================================================================
# This script creates the necessary secrets in AWS Secrets Manager for the
# backend Flask application to consume via External Secrets Operator.
#
# Usage: ./create-secrets.sh
# Prerequisites: AWS CLI configured with proper credentials
# ==============================================================================

set -e

REGION="ap-south-1"

echo "=========================================="
echo "Creating AWS Secrets Manager Secrets"
echo "Region: $REGION"
echo "=========================================="

# Generate secure random passwords
DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
FLASK_SECRET_KEY=$(openssl rand -base64 64 | tr -d "=+/" | cut -c1-64)
ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

echo ""
echo "Generated secure credentials (save these!):"
echo "-------------------------------------------"
echo "DB_PASSWORD: $DB_PASSWORD"
echo "FLASK_SECRET_KEY: $FLASK_SECRET_KEY"
echo "ADMIN_PASSWORD: $ADMIN_PASSWORD"
echo ""

# ==============================================================================
# Secret 1: Database Credentials
# ==============================================================================
echo "Creating secret: staging/backend/database"
aws secretsmanager create-secret \
  --name staging/backend/database \
  --region $REGION \
  --description "MySQL database credentials for Flask backend (staging)" \
  --secret-string "{
    \"DB_USER\": \"flask_user\",
    \"DB_PASSWORD\": \"$DB_PASSWORD\",
    \"DB_HOST\": \"flask-app-db.backend.svc.cluster.local\",
    \"DB_PORT\": \"3306\",
    \"DB_NAME\": \"flask_staging\"
  }" \
  --tags Key=Environment,Value=staging Key=Application,Value=flask-backend \
  2>/dev/null && echo "✓ Created staging/backend/database" || echo "ℹ Secret staging/backend/database already exists, updating..."

# Update if already exists
aws secretsmanager update-secret \
  --secret-id staging/backend/database \
  --region $REGION \
  --secret-string "{
    \"DB_USER\": \"flask_user\",
    \"DB_PASSWORD\": \"$DB_PASSWORD\",
    \"DB_HOST\": \"flask-app-db.backend.svc.cluster.local\",
    \"DB_PORT\": \"3306\",
    \"DB_NAME\": \"flask_staging\"
  }" \
  --description "MySQL database credentials for Flask backend (staging)" \
  2>/dev/null && echo "✓ Updated staging/backend/database"

# ==============================================================================
# Secret 2: Flask Application Secrets
# ==============================================================================
echo "Creating secret: staging/backend/flask-app"
aws secretsmanager create-secret \
  --name staging/backend/flask-app \
  --region $REGION \
  --description "Flask application secrets (SECRET_KEY, API keys)" \
  --secret-string "{
    \"SECRET_KEY\": \"$FLASK_SECRET_KEY\",
    \"API_TEST_KEY\": \"\"
  }" \
  --tags Key=Environment,Value=staging Key=Application,Value=flask-backend \
  2>/dev/null && echo "✓ Created staging/backend/flask-app" || echo "ℹ Secret staging/backend/flask-app already exists, updating..."

# Update if already exists
aws secretsmanager update-secret \
  --secret-id staging/backend/flask-app \
  --region $REGION \
  --secret-string "{
    \"SECRET_KEY\": \"$FLASK_SECRET_KEY\",
    \"API_TEST_KEY\": \"\"
  }" \
  --description "Flask application secrets (SECRET_KEY, API keys)" \
  2>/dev/null && echo "✓ Updated staging/backend/flask-app"

# ==============================================================================
# Secret 3: Admin Credentials
# ==============================================================================
echo "Creating secret: staging/backend/admin"
aws secretsmanager create-secret \
  --name staging/backend/admin \
  --region $REGION \
  --description "Initial admin user credentials for Flask backend" \
  --secret-string "{
    \"INITIAL_ADMIN_USER\": \"{\\\"user\\\": \\\"admin\\\", \\\"password\\\": \\\"$ADMIN_PASSWORD\\\"}\"
  }" \
  --tags Key=Environment,Value=staging Key=Application,Value=flask-backend \
  2>/dev/null && echo "✓ Created staging/backend/admin" || echo "ℹ Secret staging/backend/admin already exists, updating..."

# Update if already exists
aws secretsmanager update-secret \
  --secret-id staging/backend/admin \
  --region $REGION \
  --secret-string "{
    \"INITIAL_ADMIN_USER\": \"{\\\"user\\\": \\\"admin\\\", \\\"password\\\": \\\"$ADMIN_PASSWORD\\\"}\"
  }" \
  --description "Initial admin user credentials for Flask backend" \
  2>/dev/null && echo "✓ Updated staging/backend/admin"

echo ""
echo "=========================================="
echo "✓ All secrets created/updated successfully"
echo "=========================================="
echo ""
echo "Verify secrets:"
echo "aws secretsmanager list-secrets --region $REGION --filters Key=name,Values=staging/backend"
echo ""
echo "View secret value:"
echo "aws secretsmanager get-secret-value --secret-id staging/backend/database --region $REGION"
echo ""
echo "IMPORTANT: Save the generated passwords above!"
echo "Admin login credentials:"
echo "  Username: admin"
echo "  Password: $ADMIN_PASSWORD"
echo ""
