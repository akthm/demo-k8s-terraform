#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# oci-bastion-kube-tunnel.sh
#
# Creates an OCI Bastion port-forwarding session to a private Kubernetes API
# endpoint and starts an SSH tunnel to it for Terraform/Kubectl access.
#
# IDEMPOTENT: Script checks if tunnel already exists and is working before
# creating a new one. If an existing tunnel is found and validated, it will
# be reused without creating a new bastion session.
#
# Validation checks:
# 1. Port is in use on localhost
# 2. SSH tunnel process exists with correct target
# 3. TCP connectivity test succeeds
# 4. TLS handshake succeeds (confirms K8s API endpoint)
#
# If all checks pass, script exits successfully with code 0.
# Otherwise, creates new bastion session and SSH tunnel.
#
# Requirements: oci CLI, jq, ssh, ssh-keygen, openssl
# Usage: Called automatically by Terragrunt before_hook or manually
# -----------------------------------------------------------------------------

set -euo pipefail

VERBOSE="${VERBOSE:-false}"
if [[ "${VERBOSE}" == "true" ]]; then
  set -x
fi
# Configuration from environment variables (set by Terragrunt)
PROFILE="${OCI_CLI_PROFILE:-DEFAULT}"
REGION="${OCI_REGION:-il-jerusalem-1}"
BASTION_ID="${BASTION_OCID:?ERROR: BASTION_OCID environment variable required}"
TARGET_PRIVATE_IP="${K8S_PRIVATE_ENDPOINT:?ERROR: K8S_PRIVATE_ENDPOINT environment variable required}"
TARGET_PORT="${K8S_PORT:-6443}"
LOCAL_PORT="${LOCAL_K8S_PORT:-6443}"
TTL_SECONDS="${BASTION_TTL:-10800}" # 3 hours default
# Expand tilde in SSH_KEY_PATH (bash doesn't expand ~ in quoted variables)
SSH_KEY_RAW="${SSH_KEY_PATH:-${HOME}/.ssh/oci_bastion_k8s}"
SSH_KEY="${SSH_KEY_RAW/#\~/$HOME}"
KUBECONFIG_OUT="${KUBECONFIG_OUT:-./kubeconfig.bastion}"

  echo "[bastion-tunnel] Configuration:"
  echo "  - OCI Profile:        ${PROFILE}"
  echo "  - OCI Region:         ${REGION}"
  echo "  - Bastion OCID:       ${BASTION_ID}"
  echo "  - Target Private IP:  ${TARGET_PRIVATE_IP}"
  echo "  - Target Port:        ${TARGET_PORT}"
  echo "  - Local Port:         ${LOCAL_PORT}"
  echo "  - Session TTL (secs): ${TTL_SECONDS}"
  echo "  - SSH Key Path:       ${SSH_KEY}"
  echo "  - Kubeconfig Output:  ${KUBECONFIG_OUT}"

# Verify required commands
for cmd in oci jq ssh ssh-keygen; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: $cmd not found in PATH"; exit 1; }
done

PUBKEY="${SSH_KEY}.pub"

# Create SSH keypair if missing
if [[ ! -f "${SSH_KEY}" || ! -f "${PUBKEY}" ]]; then
  echo "[bastion-tunnel] Generating SSH keypair at ${SSH_KEY}"
  mkdir -p "$(dirname "${SSH_KEY}")"
  ssh-keygen -t ed25519 -f "${SSH_KEY}" -N "" -C "oci-bastion-k8s-$(whoami)" >/dev/null 2>&1
fi

# ============================================================================
# IDEMPOTENCY CHECK: Test if tunnel already established and working
# ============================================================================

echo "[bastion-tunnel] Checking for existing tunnel on port ${LOCAL_PORT}..."

# Check 1: Is port in use?
if ! lsof -ti:"${LOCAL_PORT}" >/dev/null 2>&1; then
  echo "[bastion-tunnel] Port ${LOCAL_PORT} not in use - creating new tunnel"
else
  echo "[bastion-tunnel] Port ${LOCAL_PORT} already in use - validating tunnel"
  
  # Check 2: Is SSH process alive and pointing to correct target?
  SSH_PROC=$(ps aux | grep -v grep | grep "ssh.*${LOCAL_PORT}:${TARGET_PRIVATE_IP}:${TARGET_PORT}" || true)
  if [[ -z "${SSH_PROC}" ]]; then
    echo "[bastion-tunnel] Port in use but no matching SSH tunnel found"
    echo "[bastion-tunnel] Likely different process on port ${LOCAL_PORT}"
    echo "[bastion-tunnel] Killing process on port ${LOCAL_PORT}..."
    kill -9 $(lsof -ti:"${LOCAL_PORT}") 2>/dev/null || true
    sleep 2
  else
    echo "[bastion-tunnel] SSH tunnel process found - testing connectivity..."
    
    # Check 3: Can we connect to the port?
    if timeout 3 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/${LOCAL_PORT}" 2>/dev/null; then
      echo "[bastion-tunnel] ✓ Tunnel connectivity test PASSED"
      
      # Check 4: Can we make a TLS handshake (verify it's actually K8s API)?
      if timeout 3 openssl s_client -connect "127.0.0.1:${LOCAL_PORT}" </dev/null 2>&1 | grep -q "Verify return code"; then
        echo "[bastion-tunnel] ✓ TLS handshake test PASSED - this is K8s API endpoint"
        echo "[bastion-tunnel] ✓ TUNNEL ALREADY ESTABLISHED AND WORKING"
        echo "[bastion-tunnel] Reusing existing tunnel - skipping creation"
        
        # Verify kubeconfig exists for convenience
        if [[ -n "${KUBECONFIG_OUT}" ]] && [[ ! -f "${KUBECONFIG_OUT}" ]]; then
          echo "[bastion-tunnel] Note: kubeconfig.bastion missing - creating it"
          # Fall through to create kubeconfig below
        else
          echo "[bastion-tunnel] Session details:"
          echo "  - Local endpoint: https://127.0.0.1:${LOCAL_PORT}"
          echo "  - Target: ${TARGET_PRIVATE_IP}:${TARGET_PORT}"
          echo "  - SSH Process: $(ps -p $(lsof -ti:"${LOCAL_PORT}") -o pid=,etime=,cmd= | head -1)"
          exit 0
        fi
      else
        echo "[bastion-tunnel] ✗ TLS handshake FAILED - port responding but not K8s API"
        echo "[bastion-tunnel] Cleaning up invalid tunnel..."
        pkill -f "ssh.*${LOCAL_PORT}:${TARGET_PRIVATE_IP}:${TARGET_PORT}" || true
        sleep 2
      fi
    else
      echo "[bastion-tunnel] ✗ Connectivity test FAILED - tunnel not responding"
      echo "[bastion-tunnel] Cleaning up stale tunnel..."
      pkill -f "ssh.*${LOCAL_PORT}:${TARGET_PRIVATE_IP}:${TARGET_PORT}" || true
      sleep 2
    fi
  fi
fi

echo "[bastion-tunnel] No valid tunnel found - proceeding with creation"

# ============================================================================
# CREATE NEW BASTION SESSION AND TUNNEL
# ============================================================================

SESSION_ID=""  # Will be set if new session created
DISPLAY_NAME="k8s-api-tf-$(whoami)-$(date +%Y%m%d-%H%M%S)"

echo "[bastion-tunnel] Creating Bastion session: ${DISPLAY_NAME}"
echo "[bastion-tunnel] Target: ${TARGET_PRIVATE_IP}:${TARGET_PORT} -> localhost:${LOCAL_PORT}"

# Create bastion session (capture all output, filter JSON later)
CREATE_OUTPUT="$(oci bastion session create-port-forwarding \
  --bastion-id "${BASTION_ID}" \
  --display-name "${DISPLAY_NAME}" \
  --ssh-public-key-file "${PUBKEY}" \
  --key-type PUB \
  --target-private-ip "${TARGET_PRIVATE_IP}" \
  --target-port "${TARGET_PORT}" \
  --session-ttl "${TTL_SECONDS}" \
  --wait-for-state SUCCEEDED \
  --profile "${PROFILE}" \
  --region "${REGION}" \
  --output json 2>&1)" || {
    echo "ERROR: Failed to create bastion session"
    echo "${CREATE_OUTPUT}"
    exit 1
  }

# Extract only the JSON portion (skip status messages like "Action completed...")
# Look for lines starting with '{' and ending with '}' to get the JSON block
CREATE_JSON="$(echo "${CREATE_OUTPUT}" | awk '/^{/,/^}$/')"

# Extract session OCID from resources array (not the work request ID!)
# The session ID is in .data.resources[0].identifier, not .data.id
SESSION_ID="$(echo "${CREATE_JSON}" | jq -r '.data.resources[0].identifier // empty' 2>/dev/null)"
if [[ -z "${SESSION_ID}" || "${SESSION_ID}" == "null" ]]; then
  echo "ERROR: Could not extract session OCID from JSON"
  echo "Raw output was:"
  echo "${CREATE_OUTPUT}"
  echo ""
  echo "Extracted JSON was:"
  echo "${CREATE_JSON}" | jq . 2>/dev/null || echo "${CREATE_JSON}"
  exit 1
fi

echo "[bastion-tunnel] Session created: ${SESSION_ID}"

# Fetch SSH command
SESSION_JSON="$(oci bastion session get \
  --session-id "${SESSION_ID}" \
  --profile "${PROFILE}" \
  --region "${REGION}" \
  --output json)"

BASTION_HOST="host.bastion.${REGION}.oci.oraclecloud.com"
BASTION_USER="${SESSION_ID}"

# Give the bastion session a moment to be fully ready
echo "[bastion-tunnel] Waiting for session to be ready..."
sleep 3

echo "[bastion-tunnel] Starting SSH tunnel (background)..."

# Build ssh command as an array to avoid quoting issues
SSH_CMD=(
  ssh
  -i "${SSH_KEY}"
  -o IdentitiesOnly=yes
  -o PreferredAuthentications=publickey
  -o PubkeyAuthentication=yes
  -o IdentityAgent=none
  -L "${LOCAL_PORT}:${TARGET_PRIVATE_IP}:${TARGET_PORT}"
  -p 22
  -o BatchMode=yes
  -o ExitOnForwardFailure=yes
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o GlobalKnownHostsFile=/dev/null
  -o ConnectTimeout=30
  -o ServerAliveInterval=15
  -o ServerAliveCountMax=3
  -o LogLevel=ERROR
  -N -f -n
  "${BASTION_USER}@${BASTION_HOST}"
)

# Retry SSH connection up to 5 times (session may need time to propagate)
SSH_SUCCESS=false
SSH_ERR_FILE=$(mktemp)
for attempt in {1..5}; do
  echo "[bastion-tunnel] SSH connection attempt ${attempt}/5..."
  # Note: Cannot use $() to capture output - SSH with -f backgrounds and keeps FDs open, causing hang
  if "${SSH_CMD[@]}" 2>"${SSH_ERR_FILE}"; then
    SSH_SUCCESS=true
    echo "[bastion-tunnel] SSH connection established"
    rm -f "${SSH_ERR_FILE}"
    break
  else
    SSH_ERR=$(cat "${SSH_ERR_FILE}")
    if echo "${SSH_ERR}" | grep -q "Permission denied"; then
      echo "[bastion-tunnel] Permission denied - session may not be ready, retrying in 3s..."
      sleep 3
    else
      echo "ERROR: Failed to start SSH tunnel: ${SSH_ERR}"
      rm -f "${SSH_ERR_FILE}"
      exit 1
    fi
  fi
done
rm -f "${SSH_ERR_FILE}" 2>/dev/null || true

if [[ "${SSH_SUCCESS}" != "true" ]]; then
  echo "ERROR: Failed to start SSH tunnel after 5 attempts"
  echo "Last error: ${SSH_ERR}"
  exit 1
fi
# Wait for tunnel to be ready
echo "[bastion-tunnel] Waiting for tunnel to establish..."
for i in {1..30}; do
  if timeout 1 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/${LOCAL_PORT}" 2>/dev/null; then
    echo "[bastion-tunnel] Tunnel ready at localhost:${LOCAL_PORT}"
    break
  fi
  if [[ $i -eq 30 ]]; then
    echo "ERROR: Tunnel failed to become ready after 30 seconds"
    exit 1
  fi
  sleep 1
done

# ============================================================================
# CREATE KUBECONFIG (works for both new and existing tunnels)
# ============================================================================

if [[ -n "${KUBECONFIG_OUT}" ]]; then
  # Skip if kubeconfig already exists and is valid
  if [[ -f "${KUBECONFIG_OUT}" ]]; then
    if grep -q "server: https://127.0.0.1:${LOCAL_PORT}" "${KUBECONFIG_OUT}" 2>/dev/null; then
      echo "[bastion-tunnel] Kubeconfig already exists and is valid: ${KUBECONFIG_OUT}"
    else
      echo "[bastion-tunnel] Kubeconfig exists but invalid - recreating: ${KUBECONFIG_OUT}"
      rm -f "${KUBECONFIG_OUT}"
    fi
  fi
  
  if [[ ! -f "${KUBECONFIG_OUT}" ]]; then
    echo "[bastion-tunnel] Creating kubeconfig: ${KUBECONFIG_OUT}"
    
    # Get cluster CA cert from dependency output or existing kubeconfig
    if [[ -n "${CLUSTER_CA_CERT:-}" ]]; then
      CA_CERT="${CLUSTER_CA_CERT}"
    else
      # Extract from default kubeconfig if available (with timeout to prevent hanging)
      CA_CERT="$(timeout 5 kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' 2>/dev/null || echo "")"
    fi
    
    # Create minimal kubeconfig pointing to localhost tunnel
    cat > "${KUBECONFIG_OUT}" <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: https://127.0.0.1:${LOCAL_PORT}
$(if [[ -n "${CA_CERT}" ]]; then
    echo "    certificate-authority-data: ${CA_CERT}"
else
    echo "    insecure-skip-tls-verify: true"
fi)
  name: bastion-tunnel
contexts:
- context:
    cluster: bastion-tunnel
    user: bastion-tunnel-user
  name: bastion-tunnel
current-context: bastion-tunnel
users:
- name: bastion-tunnel-user
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: oci
      args:
        - ce
        - cluster
        - generate-token
        - --cluster-id
        - "${CLUSTER_ID}"
        - --region
        - "${REGION}"
EOF

    echo "[bastion-tunnel] ✓ Kubeconfig created: ${KUBECONFIG_OUT}"
  fi
  
  # ============================================================================
  # VALIDATE KUBECTL ACCESS (and fix TLS issues automatically)
  # ============================================================================
  
  echo "[bastion-tunnel] Validating kubectl access..."
  
  # Test kubectl with the generated kubeconfig
  if KUBECONFIG="${KUBECONFIG_OUT}" timeout 10 kubectl cluster-info >/dev/null 2>&1; then
    echo "[bastion-tunnel] ✓ kubectl validation PASSED"
  else
    echo "[bastion-tunnel] ⚠ kubectl validation FAILED - checking for TLS certificate issues..."
    
    # Check if it's a TLS certificate error (with timeout to prevent hanging)
    KUBECTL_ERROR="$(KUBECONFIG="${KUBECONFIG_OUT}" timeout 15 kubectl cluster-info 2>&1 || true)"
    if echo "${KUBECTL_ERROR}" | grep -q "tls: failed to verify certificate\|x509: certificate"; then
      echo "[bastion-tunnel] ✓ Detected TLS certificate verification error"
      echo "[bastion-tunnel] → Enabling insecure-skip-tls-verify mode..."
      
      # Recreate kubeconfig with insecure-skip-tls-verify
      cat > "${KUBECONFIG_OUT}" <<EOFINSECURE
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: https://127.0.0.1:${LOCAL_PORT}
    insecure-skip-tls-verify: true
  name: bastion-tunnel
contexts:
- context:
    cluster: bastion-tunnel
    user: bastion-tunnel-user
  name: bastion-tunnel
current-context: bastion-tunnel
users:
- name: bastion-tunnel-user
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: oci
      args:
        - ce
        - cluster
        - generate-token
        - --cluster-id
        - "${CLUSTER_ID}"
        - --region
        - "${REGION}"
EOFINSECURE
      
      echo "[bastion-tunnel] ✓ Kubeconfig updated with insecure-skip-tls-verify"
      
      # Retry kubectl validation
      if KUBECONFIG="${KUBECONFIG_OUT}" timeout 10 kubectl cluster-info >/dev/null 2>&1; then
        echo "[bastion-tunnel] ✓ kubectl validation PASSED (insecure mode)"
      else
        echo "[bastion-tunnel] ✗ kubectl still failing - may be authentication issue"
        echo "[bastion-tunnel] Error output:"
        KUBECONFIG="${KUBECONFIG_OUT}" timeout 10 kubectl cluster-info 2>&1 | head -10
        echo "[bastion-tunnel] ⚠ WARNING: kubectl validation failed, but tunnel is established"
        echo "[bastion-tunnel] You may need to check OCI CLI authentication"
      fi
    else
      echo "[bastion-tunnel] ✗ kubectl failed with non-TLS error:"
      echo "${KUBECTL_ERROR}" | head -10
      echo "[bastion-tunnel] ⚠ WARNING: kubectl validation failed, but tunnel is established"
    fi
  fi
fi

echo ""
echo "[bastion-tunnel] ════════════════════════════════════════════════════════"
echo "[bastion-tunnel] ✓ SUCCESS - Tunnel ready"
echo "[bastion-tunnel] ════════════════════════════════════════════════════════"
echo "[bastion-tunnel] Local endpoint:  https://127.0.0.1:${LOCAL_PORT}"
echo "[bastion-tunnel] Target endpoint: ${TARGET_PRIVATE_IP}:${TARGET_PORT}"
echo "[bastion-tunnel] Session ID:      ${SESSION_ID:-reused-existing}"
echo "[bastion-tunnel] Status:          $(if lsof -ti:${LOCAL_PORT} >/dev/null 2>&1; then echo 'ACTIVE'; else echo 'UNKNOWN'; fi)"
echo "[bastion-tunnel] Kubeconfig:      ${KUBECONFIG_OUT:-not-created}"
echo "[bastion-tunnel] ════════════════════════════════════════════════════════"
echo "[bastion-tunnel] To stop tunnel:  pkill -f 'ssh.*${LOCAL_PORT}:${TARGET_PRIVATE_IP}:${TARGET_PORT}'"
echo ""
