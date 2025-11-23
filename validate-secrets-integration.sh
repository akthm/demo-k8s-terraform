#!/bin/bash
# ==============================================================================
# AWS Secrets Manager Integration - Post-Deployment Validation Script
# ==============================================================================
# This script validates the External Secrets Operator integration
# Run this after deploying ClusterSecretStore and ExternalSecrets to GitOps repo
#
# Usage: ./validate-secrets-integration.sh
# ==============================================================================

set -e

REGION="ap-south-1"
BACKEND_NAMESPACE="backend"
ESO_NAMESPACE="external-secrets"

echo "=========================================="
echo "AWS Secrets Manager Integration Validation"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track overall status
ERRORS=0

validate() {
    local test_name="$1"
    local command="$2"
    
    echo -n "Testing: $test_name ... "
    if eval "$command" &>/dev/null; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
}

validate_with_output() {
    local test_name="$1"
    local command="$2"
    local expected="$3"
    
    echo -n "Testing: $test_name ... "
    output=$(eval "$command" 2>/dev/null || echo "")
    if [[ "$output" == *"$expected"* ]]; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        echo "  Expected: $expected"
        echo "  Got: $output"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
}

echo "=== 1. AWS Secrets Manager Validation ==="
echo ""

validate "Secret: staging/backend/database exists" \
    "aws secretsmanager describe-secret --secret-id staging/backend/database --region $REGION"

validate "Secret: staging/backend/flask-app exists" \
    "aws secretsmanager describe-secret --secret-id staging/backend/flask-app --region $REGION"

validate "Secret: staging/backend/admin exists" \
    "aws secretsmanager describe-secret --secret-id staging/backend/admin --region $REGION"

echo ""
echo "=== 2. External Secrets Operator Validation ==="
echo ""

validate "External Secrets namespace exists" \
    "kubectl get namespace $ESO_NAMESPACE"

validate "External Secrets Operator pod is running" \
    "kubectl get pods -n $ESO_NAMESPACE -l app.kubernetes.io/name=external-secrets --field-selector=status.phase=Running"

validate "External Secrets cert-controller is running" \
    "kubectl get pods -n $ESO_NAMESPACE -l app.kubernetes.io/component=cert-controller --field-selector=status.phase=Running"

validate "External Secrets webhook is running" \
    "kubectl get pods -n $ESO_NAMESPACE -l app.kubernetes.io/component=webhook --field-selector=status.phase=Running"

validate_with_output "Service account has IRSA annotation" \
    "kubectl get sa external-secrets-sa -n $ESO_NAMESPACE -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'" \
    "arn:aws:iam::"

echo ""
echo "=== 3. ClusterSecretStore Validation ==="
echo ""

if validate "ClusterSecretStore exists" \
    "kubectl get clustersecretstore aws-secrets-manager"; then
    
    validate_with_output "ClusterSecretStore is Ready" \
        "kubectl get clustersecretstore aws-secrets-manager -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" \
        "True"
fi

echo ""
echo "=== 4. Backend Namespace Validation ==="
echo ""

if ! validate "Backend namespace exists" \
    "kubectl get namespace $BACKEND_NAMESPACE"; then
    echo -e "${YELLOW}⚠ Backend namespace not found. ExternalSecrets validation skipped.${NC}"
    echo -e "${YELLOW}⚠ Deploy backend application first via ArgoCD.${NC}"
else
    echo ""
    echo "=== 5. ExternalSecret Resources Validation ==="
    echo ""
    
    if validate "ExternalSecret: flask-app-db-credentials exists" \
        "kubectl get externalsecret flask-app-db-credentials -n $BACKEND_NAMESPACE"; then
        
        validate_with_output "ExternalSecret: flask-app-db-credentials is synced" \
            "kubectl get externalsecret flask-app-db-credentials -n $BACKEND_NAMESPACE -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" \
            "True"
    fi
    
    if validate "ExternalSecret: flask-app-secrets exists" \
        "kubectl get externalsecret flask-app-secrets -n $BACKEND_NAMESPACE"; then
        
        validate_with_output "ExternalSecret: flask-app-secrets is synced" \
            "kubectl get externalsecret flask-app-secrets -n $BACKEND_NAMESPACE -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" \
            "True"
    fi
    
    if validate "ExternalSecret: flask-app-admin-credentials exists" \
        "kubectl get externalsecret flask-app-admin-credentials -n $BACKEND_NAMESPACE"; then
        
        validate_with_output "ExternalSecret: flask-app-admin-credentials is synced" \
            "kubectl get externalsecret flask-app-admin-credentials -n $BACKEND_NAMESPACE -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" \
            "True"
    fi
    
    echo ""
    echo "=== 6. Kubernetes Secrets Validation ==="
    echo ""
    
    if validate "K8s Secret: flask-app-db-credentials exists" \
        "kubectl get secret flask-app-db-credentials -n $BACKEND_NAMESPACE"; then
        
        validate_with_output "Secret has DB_USER key" \
            "kubectl get secret flask-app-db-credentials -n $BACKEND_NAMESPACE -o jsonpath='{.data.DB_USER}'" \
            "Zmxhc2tfdXNlcg"  # base64 of "flask_user"
        
        validate "Secret has DB_PASSWORD key" \
            "kubectl get secret flask-app-db-credentials -n $BACKEND_NAMESPACE -o jsonpath='{.data.DB_PASSWORD}'"
        
        validate "Secret has DB_HOST key" \
            "kubectl get secret flask-app-db-credentials -n $BACKEND_NAMESPACE -o jsonpath='{.data.DB_HOST}'"
    fi
    
    if validate "K8s Secret: flask-app-secrets exists" \
        "kubectl get secret flask-app-secrets -n $BACKEND_NAMESPACE"; then
        
        validate "Secret has SECRET_KEY key" \
            "kubectl get secret flask-app-secrets -n $BACKEND_NAMESPACE -o jsonpath='{.data.SECRET_KEY}'"
    fi
    
    validate "K8s Secret: flask-app-admin-credentials exists" \
        "kubectl get secret flask-app-admin-credentials -n $BACKEND_NAMESPACE"
fi

echo ""
echo "=========================================="
echo "Validation Summary"
echo "=========================================="

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ All validations passed!${NC}"
    echo ""
    echo "Next Steps:"
    echo "1. Verify backend pods are using the secrets:"
    echo "   kubectl get pods -n $BACKEND_NAMESPACE"
    echo "   kubectl describe pod <pod-name> -n $BACKEND_NAMESPACE | grep -A 10 'Environment Variables'"
    echo ""
    echo "2. Test application functionality with new secrets"
    echo ""
    echo "3. Monitor External Secrets Operator logs:"
    echo "   kubectl logs -n $ESO_NAMESPACE -l app.kubernetes.io/name=external-secrets --tail=50 -f"
    exit 0
else
    echo -e "${RED}✗ $ERRORS validation(s) failed${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "1. Check External Secrets Operator logs:"
    echo "   kubectl logs -n $ESO_NAMESPACE -l app.kubernetes.io/name=external-secrets --tail=100"
    echo ""
    echo "2. Describe ClusterSecretStore:"
    echo "   kubectl describe clustersecretstore aws-secrets-manager"
    echo ""
    echo "3. Check ExternalSecret status:"
    echo "   kubectl describe externalsecret flask-app-db-credentials -n $BACKEND_NAMESPACE"
    echo ""
    echo "4. Verify IRSA permissions:"
    echo "   kubectl get sa external-secrets-sa -n $ESO_NAMESPACE -o yaml"
    echo ""
    echo "5. Review implementation guide:"
    echo "   cat /home/akthm/Devops/portfolio/terraform/IMPLEMENTATION_SUMMARY.md"
    exit 1
fi
