#!/bin/bash
# ==============================================================================
# Post-Terraform Validation and Auto-Fix Script
# ==============================================================================
# This script validates and fixes common issues after terraform apply
#
# Usage: ./post-terraform-validation.sh
# ==============================================================================

set -e

REGION="ap-south-1"
CLUSTER_NAME="akthm-cluster"
BACKEND_NS="backend"
ESO_NS="external-secrets"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ERRORS=0
FIXES=0

echo -e "${BLUE}=========================================="
echo "Post-Terraform Validation & Auto-Fix"
echo -e "==========================================${NC}\n"

# Function to validate and auto-fix
validate_and_fix() {
    local check_name="$1"
    local check_cmd="$2"
    local fix_cmd="$3"
    
    echo -n "Checking: $check_name ... "
    if eval "$check_cmd" &>/dev/null; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        ERRORS=$((ERRORS + 1))
        
        if [ -n "$fix_cmd" ]; then
            echo -n "  Applying fix ... "
            if eval "$fix_cmd" &>/dev/null; then
                echo -e "${GREEN}Fixed!${NC}"
                FIXES=$((FIXES + 1))
                return 0
            else
                echo -e "${RED}Fix failed${NC}"
                return 1
            fi
        fi
        return 1
    fi
}

# ==============================================================================
# 1. Kubernetes Connectivity
# ==============================================================================
echo -e "${BLUE}=== 1. Kubernetes Connectivity ===${NC}\n"

validate_and_fix \
    "kubectl configured for cluster" \
    "kubectl cluster-info" \
    "aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME"

validate_and_fix \
    "Cluster nodes are Ready" \
    "kubectl get nodes --no-headers | grep -v NotReady"

# ==============================================================================
# 2. External Secrets Operator
# ==============================================================================
echo -e "\n${BLUE}=== 2. External Secrets Operator ===${NC}\n"

validate_and_fix \
    "External Secrets namespace exists" \
    "kubectl get namespace $ESO_NS"

validate_and_fix \
    "External Secrets Operator running" \
    "kubectl get pods -n $ESO_NS -l app.kubernetes.io/name=external-secrets --field-selector=status.phase=Running --no-headers | wc -l | grep -v 0"

validate_and_fix \
    "ClusterSecretStore is Ready" \
    "kubectl get clustersecretstore aws-secrets-manager -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep True"

# ==============================================================================
# 3. AWS Secrets Manager
# ==============================================================================
echo -e "\n${BLUE}=== 3. AWS Secrets Manager Secrets ===${NC}\n"

validate_and_fix \
    "Secret: staging/backend/database" \
    "aws secretsmanager describe-secret --secret-id staging/backend/database --region $REGION"

validate_and_fix \
    "Secret: staging/backend/flask-app" \
    "aws secretsmanager describe-secret --secret-id staging/backend/flask-app --region $REGION"

validate_and_fix \
    "Secret: staging/backend/admin" \
    "aws secretsmanager describe-secret --secret-id staging/backend/admin --region $REGION"

# ==============================================================================
# 4. Backend Namespace
# ==============================================================================
echo -e "\n${BLUE}=== 4. Backend Application ===${NC}\n"

validate_and_fix \
    "Backend namespace exists" \
    "kubectl get namespace $BACKEND_NS"

if kubectl get namespace $BACKEND_NS &>/dev/null; then
    
    # Check and fix MySQL ExternalSecret
    validate_and_fix \
        "MySQL credentials ExternalSecret exists" \
        "kubectl get externalsecret mysql-db-secret -n $BACKEND_NS" \
        "cat <<'EOF' | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: mysql-db-secret
  namespace: $BACKEND_NS
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: flask-app-db
    creationPolicy: Owner
    template:
      type: Opaque
      data:
        mysql-root-password: \"{{ .DB_PASSWORD }}\"
        mysql-password: \"{{ .DB_PASSWORD }}\"
  data:
    - secretKey: DB_PASSWORD
      remoteRef:
        key: staging/backend/database
        property: DB_PASSWORD
EOF"
    
    validate_and_fix \
        "MySQL secret (flask-app-db) created" \
        "kubectl get secret flask-app-db -n $BACKEND_NS"
    
    validate_and_fix \
        "Flask app secrets synced" \
        "kubectl get externalsecret -n $BACKEND_NS -o jsonpath='{.items[*].status.conditions[?(@.type==\"Ready\")].status}' | grep -v False"
    
    # Check StorageClass
    validate_and_fix \
        "StorageClass 'standard' exists" \
        "kubectl get storageclass standard" \
        "cat <<'EOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: \"true\"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Delete
EOF"
    
    # Check PVC
    validate_and_fix \
        "MySQL PVC is Bound" \
        "kubectl get pvc -n $BACKEND_NS -o jsonpath='{.items[?(@.metadata.name==\"data-flask-app-db-0\")].status.phase}' | grep Bound"
    
    # Check MySQL Pod
    validate_and_fix \
        "MySQL pod is Running" \
        "kubectl get pod flask-app-db-0 -n $BACKEND_NS --no-headers 2>/dev/null | grep Running"
    
    validate_and_fix \
        "MySQL pod is Ready" \
        "kubectl get pod flask-app-db-0 -n $BACKEND_NS -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null | grep True" \
        "kubectl delete pod flask-app-db-0 -n $BACKEND_NS 2>/dev/null; sleep 60; kubectl wait --for=condition=Ready pod/flask-app-db-0 -n $BACKEND_NS --timeout=120s"
    
    # Check Flask App Pod
    FLASK_POD=$(kubectl get pods -n $BACKEND_NS -l app=flask-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$FLASK_POD" ]; then
        validate_and_fix \
            "Flask app pod is Running" \
            "kubectl get pod $FLASK_POD -n $BACKEND_NS --no-headers | grep Running"
        
        validate_and_fix \
            "Flask app pod is Ready" \
            "kubectl get pod $FLASK_POD -n $BACKEND_NS -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep True"
    fi
fi

# ==============================================================================
# Summary
# ==============================================================================
echo -e "\n${BLUE}=========================================="
echo "Validation Summary"
echo -e "==========================================${NC}"

TOTAL_CHECKS=$((ERRORS + FIXES))

echo -e "${GREEN}Passed:${NC}  $((TOTAL_CHECKS - ERRORS))"
echo -e "${YELLOW}Fixed:${NC}   $FIXES"
echo -e "${RED}Failed:${NC}  $((ERRORS - FIXES))"
echo -e "${BLUE}Total:${NC}   Checks performed"

echo ""

if [ $((ERRORS - FIXES)) -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed or auto-fixed!${NC}"
    echo ""
    echo "System is ready. You can now:"
    echo "  1. Access Flask app: kubectl port-forward -n backend svc/flask-app 8000:8000"
    echo "  2. Check logs: kubectl logs -n backend -l app=flask-app --tail=50"
    echo "  3. Access MySQL: kubectl port-forward -n backend svc/flask-app-db 3306:3306"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Some checks failed and could not be auto-fixed${NC}"
    echo ""
    echo "Manual intervention required. Check:"
    echo "  1. kubectl get pods -n backend"
    echo "  2. kubectl get externalsecret -n backend"
    echo "  3. kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets"
    echo ""
    exit 1
fi
