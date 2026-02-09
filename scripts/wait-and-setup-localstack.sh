#!/bin/bash
################################################################################
# Wait for LocalStack and Setup Secrets
#
# This script:
# 1. Waits for LocalStack pod to be ready
# 2. Port-forwards LocalStack service to localhost:4566
# 3. Runs the secrets setup script
#
# Usage: ./wait-and-setup-localstack.sh [context] [namespace]
################################################################################

set -e

# Configuration
KUBE_CONTEXT="${1:-kind-local-dev}"
NAMESPACE="${2:-localstack}"
SERVICE_NAME="local-stack-localstack"
LOCAL_PORT="4566"
REMOTE_PORT="4566"
MAX_WAIT_SECONDS=300
POLL_INTERVAL=5

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== LocalStack Setup for Local Development ===${NC}"
echo "Context: ${KUBE_CONTEXT}"
echo "Namespace: ${NAMESPACE}"
echo ""

################################################################################
# Function: Wait for namespace to exist
################################################################################
wait_for_namespace() {
    echo -e "${YELLOW}Checking if namespace '${NAMESPACE}' exists...${NC}"
    
    local elapsed=0
    while [ $elapsed -lt $MAX_WAIT_SECONDS ]; do
        if kubectl get namespace "${NAMESPACE}" --context="${KUBE_CONTEXT}" &>/dev/null; then
            echo -e "${GREEN}✓ Namespace '${NAMESPACE}' exists${NC}"
            return 0
        fi
        echo "Waiting for namespace... (${elapsed}s/${MAX_WAIT_SECONDS}s)"
        sleep $POLL_INTERVAL
        elapsed=$((elapsed + POLL_INTERVAL))
    done
    
    echo -e "${RED}✗ Namespace '${NAMESPACE}' not found after ${MAX_WAIT_SECONDS}s${NC}"
    return 1
}

################################################################################
# Function: Wait for LocalStack deployment
################################################################################
wait_for_localstack() {
    echo -e "${YELLOW}Waiting for LocalStack pod to be ready...${NC}"
    
    local elapsed=0
    while [ $elapsed -lt $MAX_WAIT_SECONDS ]; do
        # Check if pod exists and is running
        local pod_status=$(kubectl get pods -n "${NAMESPACE}" \
            --context="${KUBE_CONTEXT}" \
            -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
        
        if [ "$pod_status" = "Running" ]; then
            # Check if all containers are ready
            local ready=$(kubectl get pods -n "${NAMESPACE}" \
                --context="${KUBE_CONTEXT}" \
                -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
            
            if [ "$ready" = "True" ]; then
                echo -e "${GREEN}✓ LocalStack pod is ready${NC}"
                return 0
            fi
        fi
        
        echo "Pod status: ${pod_status} (${elapsed}s/${MAX_WAIT_SECONDS}s)"
        sleep $POLL_INTERVAL
        elapsed=$((elapsed + POLL_INTERVAL))
    done
    
    echo -e "${RED}✗ LocalStack pod did not become ready after ${MAX_WAIT_SECONDS}s${NC}"
    return 1
}

################################################################################
# Function: Check if port-forward is already running
################################################################################
cleanup_existing_port_forward() {
    echo -e "${YELLOW}Checking for existing port-forwards on port ${LOCAL_PORT}...${NC}"
    
    # Find and kill any existing kubectl port-forward on this port
    local pids=$(lsof -ti:${LOCAL_PORT} 2>/dev/null || true)
    if [ -n "$pids" ]; then
        echo -e "${YELLOW}Killing existing process(es) on port ${LOCAL_PORT}: ${pids}${NC}"
        kill -9 $pids 2>/dev/null || true
        sleep 2
    fi
}

################################################################################
# Function: Start port-forward in background
################################################################################
start_port_forward() {
    echo -e "${YELLOW}Starting port-forward: localhost:${LOCAL_PORT} -> ${SERVICE_NAME}:${REMOTE_PORT}${NC}"
    
    # Start port-forward in background and capture PID
    kubectl port-forward \
        -n "${NAMESPACE}" \
        --context="${KUBE_CONTEXT}" \
        "svc/${SERVICE_NAME}" \
        "${LOCAL_PORT}:${REMOTE_PORT}" \
        >/dev/null 2>&1 &
    
    local PF_PID=$!
    echo $PF_PID > /tmp/localstack-port-forward.pid
    
    # Wait a moment for port-forward to establish
    sleep 3
    
    # Verify port-forward is working
    if ! ps -p $PF_PID > /dev/null 2>&1; then
        echo -e "${RED}✗ Port-forward failed to start${NC}"
        return 1
    fi
    
    # Test connection
    if curl -s "http://localhost:${LOCAL_PORT}/_localstack/health" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Port-forward established (PID: ${PF_PID})${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ Port-forward started but LocalStack not responding yet...${NC}"
        return 0
    fi
}

################################################################################
# Function: Wait for LocalStack to respond
################################################################################
wait_for_localstack_api() {
    echo -e "${YELLOW}Waiting for LocalStack API to respond...${NC}"
    
    local elapsed=0
    while [ $elapsed -lt 60 ]; do
        if curl -s "http://localhost:${LOCAL_PORT}/_localstack/health" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ LocalStack API is responding${NC}"
            return 0
        fi
        echo "Waiting for API... (${elapsed}s/60s)"
        sleep 3
        elapsed=$((elapsed + 3))
    done
    
    echo -e "${RED}✗ LocalStack API did not respond after 60s${NC}"
    return 1
}

################################################################################
# Function: Run secrets setup script
################################################################################
run_secrets_setup() {
    local script_path="$(dirname "$0")/subscripts/setupsecrets-localstack.sh"
    
    echo -e "${YELLOW}Running secrets setup script...${NC}"
    echo "Script: ${script_path}"
    
    if [ ! -f "$script_path" ]; then
        echo -e "${RED}✗ Secrets setup script not found: ${script_path}${NC}"
        return 1
    fi
    
    if [ ! -x "$script_path" ]; then
        chmod +x "$script_path"
    fi
    
    # Set environment variables for the script
    export LOCALSTACK_ENDPOINT="http://localhost:${LOCAL_PORT}"
    export AWS_ENDPOINT_URL="http://localhost:${LOCAL_PORT}"
    export AWS_ACCESS_KEY_ID="test"
    export AWS_SECRET_ACCESS_KEY="test"
    export AWS_DEFAULT_REGION="us-east-1"
    
    echo ""
    echo -e "${BLUE}--- Secrets Setup Output ---${NC}"
    if bash "$script_path"; then
        echo -e "${GREEN}✓ Secrets setup completed successfully${NC}"
        return 0
    else
        echo -e "${RED}✗ Secrets setup failed${NC}"
        return 1
    fi
}

################################################################################
# Cleanup function
################################################################################
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleaning up...${NC}"
    
    if [ -f /tmp/localstack-port-forward.pid ]; then
        local PF_PID=$(cat /tmp/localstack-port-forward.pid)
        if ps -p $PF_PID > /dev/null 2>&1; then
            echo "Stopping port-forward (PID: ${PF_PID})"
            kill $PF_PID 2>/dev/null || true
        fi
        rm -f /tmp/localstack-port-forward.pid
    fi
}

# Set up trap for cleanup on exit
trap cleanup EXIT INT TERM

################################################################################
# Main execution
################################################################################
main() {
    echo -e "${BLUE}Step 1: Wait for namespace${NC}"
    wait_for_namespace || exit 1
    
    echo ""
    echo -e "${BLUE}Step 2: Wait for LocalStack pod${NC}"
    wait_for_localstack || exit 1
    
    echo ""
    echo -e "${BLUE}Step 3: Setup port-forward${NC}"
    cleanup_existing_port_forward
    start_port_forward || exit 1
    
    echo ""
    echo -e "${BLUE}Step 4: Wait for LocalStack API${NC}"
    wait_for_localstack_api || exit 1
    
    echo ""
    echo -e "${BLUE}Step 5: Run secrets setup${NC}"
    run_secrets_setup || exit 1
    
    echo ""
    echo -e "${GREEN}=== LocalStack setup completed successfully ===${NC}"
    echo -e "${YELLOW}Note: Port-forward will be stopped automatically${NC}"
    
    return 0
}

# Run main function
main
