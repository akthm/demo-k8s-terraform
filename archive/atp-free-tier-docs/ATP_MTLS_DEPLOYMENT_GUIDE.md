# ATP mTLS Wallet Implementation - Deployment Guide

## Overview

This implementation enables mTLS wallet-based authentication for ATP database connections by:
1. Storing wallet ZIP in OCI Object Storage bucket (free tier, 20GB)
2. Storing bucket metadata in OCI Vault secrets
3. OKE pods download wallet using instance principal auth
4. InitContainers unzip wallet to mounted directory
5. Applications use TNS aliases for connections

## Phase 1: Deploy Infrastructure (Terragrunt)

### Step 1: Deploy Wallet Bucket

```bash
cd /workspaces/docker-in-docker/workdir/terraform
source .env.terraform-backend

cd live/oci-staging/wallet-bucket
terragrunt init
terragrunt plan
terragrunt apply

# Save outputs
terragrunt output
# Expected:
# bucket_name = "oke-staging-atp-wallets"
# bucket_namespace = "<your-tenancy-ocid>"
```

### Step 2: Update Vault with Wallet Bucket Metadata

```bash
cd ../vault
terragrunt init
terragrunt plan
terragrunt apply

# Verify wallet bucket secret was created
terragrunt output adb_wallet_bucket_info_secret_id
# Save this OCID: ocid1.vaultsecret.oc1.il-jerusalem-1.xxx
```

### Step 3: Enable mTLS on ATP

```bash
cd ../atp
terragrunt plan
# Review: require_mtls will change from false to true
terragrunt apply

# Verify mTLS is enabled
VAULT_ID=$(cd ../vault && terragrunt output -raw vault_id)
KEY_ID=$(cd ../vault && terragrunt output -raw key_id)
ATP_ID=$(terragrunt output -raw atp_id)

oci db autonomous-database get \
  --autonomous-database-id "$ATP_ID" \
  --profile DEFAULT \
  --region il-jerusalem-1 \
  | jq '.data."is-mtls-connection-required"'
# Expected: true
```

## Phase 2: Upload Wallet to Object Storage

### Step 1: Download Wallet from OCI Console

1. Navigate to OCI Console: https://cloud.oracle.com/
2. Go to: **Autonomous Databases** > **stagingdb**
3. Click **DB Connection**
4. Click **Download Wallet**
5. Enter wallet password (SAVE THIS - needed for pod extraction)
   - Recommended: Strong password, 16+ chars
   - Example: `Wa11et!Passw0rd#2026`
6. Save wallet as: `~/Downloads/Wallet_stagingdb.zip`

### Step 2: Upload Wallet to Bucket

```bash
# Get bucket details
cd /workspaces/docker-in-docker/workdir/terraform/live/oci-staging/wallet-bucket
BUCKET_NAME=$(terragrunt output -raw bucket_name)
BUCKET_NAMESPACE=$(terragrunt output -raw bucket_namespace)

# Upload wallet
oci os object put \
  --bucket-name "$BUCKET_NAME" \
  --namespace-name "$BUCKET_NAMESPACE" \
  --file ~/Downloads/Wallet_stagingdb.zip \
  --name "stagingdb_wallet.zip" \
  --profile DEFAULT \
  --region il-jerusalem-1

# Verify upload
oci os object head \
  --bucket-name "$BUCKET_NAME" \
  --namespace-name "$BUCKET_NAMESPACE" \
  --name "stagingdb_wallet.zip" \
  --profile DEFAULT \
  --region il-jerusalem-1
# Expected: content-length > 0, last-modified timestamp
```

### Step 3: Store Wallet Password in Vault

```bash
cd ../vault
VAULT_ID=$(terragrunt output -raw vault_id)
KEY_ID=$(terragrunt output -raw key_id)
COMPARTMENT_ID=$TG_VAR_oci_compartment_id

# Create wallet password secret
WALLET_PASSWORD="Wa11et!Passw0rd#2026"  # Use your actual password

oci vault secret create-base64 \
  --compartment-id "$COMPARTMENT_ID" \
  --vault-id "$VAULT_ID" \
  --key-id "$KEY_ID" \
  --secret-name "adb-wallet-password" \
  --secret-content-content "$(echo -n "$WALLET_PASSWORD" | base64)" \
  --description "ATP wallet ZIP password for extraction" \
  --profile DEFAULT \
  --region il-jerusalem-1

# Save the secret OCID from output
# Expected: "id": "ocid1.vaultsecret.oc1.il-jerusalem-1.xxx"
```

## Phase 3: GitOps Configuration (ArgoCD Repository)

### Files to Create in GitOps Repo

Location: `apps/oci-staging/external-secrets/`

**File 1: `adb-wallet-bucket-secret.yaml`**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: adb-wallet-bucket-info
  namespace: backend
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: oci-vault
    kind: ClusterSecretStore
  
  target:
    name: adb-wallet-bucket-info
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        WALLET_BUCKET_NAME: "{{ .bucket_name }}"
        WALLET_OBJECT_NAME: "{{ .object_name }}"
        WALLET_NAMESPACE: "{{ .namespace }}"
        WALLET_REGION: "{{ .region }}"
  
  dataFrom:
    - extract:
        key: adb-wallet-bucket-info
```

**File 2: `adb-wallet-password-secret.yaml`**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: adb-wallet-password
  namespace: backend
spec:
  refreshInterval: 24h
  secretStoreRef:
    name: oci-vault
    kind: ClusterSecretStore
  
  target:
    name: adb-wallet-password
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        password: "{{ .password }}"
  
  dataFrom:
    - extract:
        key: adb-wallet-password
```

**File 3: Update `kustomization.yaml`**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - adb-wallet-bucket-secret.yaml
  - adb-wallet-password-secret.yaml
  # ... existing resources ...

commonAnnotations:
  argocd.argoproj.io/sync-wave: "1"
```

### Update Application Deployments

Example for Flask backend in `apps/oci-staging/backend/templates/deployment.yaml`:

Add volumes and initContainers (see full example in main plan document).

Key changes:
- Add `wallet-download` emptyDir volume
- Add `wallet-dir` emptyDir volume
- Add initContainer `wallet-downloader` with OCI CLI image
- Add initContainer `wallet-extractor` with busybox
- Main container mounts `/opt/oracle/wallet`
- Set `TNS_ADMIN=/opt/oracle/wallet` env var
- Update connection string to use TNS alias: `@stagingdb_high`

## Phase 4: Verification

### Test Wallet Download in Pod

```bash
# Deploy a test pod with OCI CLI
kubectl run oci-cli-test \
  -n backend \
  --image=ghcr.io/oracle/oci-cli:3.36.2 \
  --command -- sleep 3600

# Exec into pod
kubectl exec -it -n backend oci-cli-test -- bash

# Inside pod - test instance principal auth
oci iam region list --auth instance_principal

# Test bucket access
oci os object list \
  --auth instance_principal \
  --bucket-name "oke-staging-atp-wallets" \
  --namespace-name "<your-namespace>"

# Download wallet
oci os object get \
  --auth instance_principal \
  --bucket-name "oke-staging-atp-wallets" \
  --namespace-name "<your-namespace>" \
  --name "stagingdb_wallet.zip" \
  --file /tmp/wallet.zip

# Verify download
ls -lh /tmp/wallet.zip

# Cleanup
exit
kubectl delete pod oci-cli-test -n backend
```

### Verify ExternalSecrets Synced

```bash
# Check bucket info secret
kubectl get externalsecret -n backend adb-wallet-bucket-info
kubectl get secret -n backend adb-wallet-bucket-info -o yaml

# Check wallet password secret
kubectl get externalsecret -n backend adb-wallet-password
kubectl get secret -n backend adb-wallet-password -o jsonpath='{.data.password}' | base64 -d

# Verify secret values
kubectl get secret -n backend adb-wallet-bucket-info -o jsonpath='{.data.WALLET_BUCKET_NAME}' | base64 -d
```

### Test Database Connection with Wallet

```bash
# After deploying updated application with initContainers
kubectl get pods -n backend

# Check initContainer logs
kubectl logs -n backend <pod-name> -c wallet-downloader
kubectl logs -n backend <pod-name> -c wallet-extractor

# Verify wallet files exist
kubectl exec -n backend <pod-name> -- ls -la /opt/oracle/wallet
# Expected files: cwallet.sso, tnsnames.ora, sqlnet.ora

# Test database connection
kubectl exec -n backend <pod-name> -- \
  python -c "import oracledb; conn = oracledb.connect(user='ADMIN', password='<atp-admin-password>', dsn='stagingdb_high'); print('✓ Connection successful'); conn.close()"
```

## Wallet Rotation Process

### When to Rotate
- Wallet expiration (typically 1 year)
- Security policy requirements
- Credential compromise

### Rotation Steps

```bash
# 1. Download new wallet from OCI Console
# Save as: ~/Downloads/Wallet_stagingdb_new.zip

# 2. Upload to bucket (creates new version)
cd /workspaces/docker-in-docker/workdir/terraform/live/oci-staging/wallet-bucket
BUCKET_NAME=$(terragrunt output -raw bucket_name)
BUCKET_NAMESPACE=$(terragrunt output -raw bucket_namespace)

oci os object put \
  --bucket-name "$BUCKET_NAME" \
  --namespace-name "$BUCKET_NAMESPACE" \
  --file ~/Downloads/Wallet_stagingdb_new.zip \
  --name "stagingdb_wallet.zip" \
  --profile DEFAULT \
  --region il-jerusalem-1

# 3. Update wallet password if changed
# (repeat Phase 2 Step 3 with new password)

# 4. Trigger pod rollout
kubectl rollout restart deployment -n backend <deployment-name>
kubectl rollout restart statefulset -n keycloak keycloak

# 5. Monitor rollout
kubectl rollout status deployment -n backend <deployment-name>

# 6. Verify new wallet working
kubectl logs -n backend <new-pod-name> -c wallet-downloader
kubectl exec -n backend <new-pod-name> -- ls -la /opt/oracle/wallet
```

## Troubleshooting

### Issue: Wallet Download Fails

**Symptoms:**
```
ServiceError: Authorization failed or requested resource not found
```

**Fix:**
```bash
# Verify IAM policy includes Object Storage
cd /workspaces/docker-in-docker/workdir/terraform/live/oci-staging/vault
terragrunt output policy_id

# Check policy statements
oci iam policy get --policy-id <policy-ocid> | jq '.data.statements'

# Expected statements include:
# "Allow dynamic-group ... to read buckets ..."
# "Allow dynamic-group ... to read objects ..."
```

### Issue: Wallet Extraction Fails

**Symptoms:**
```
Archive:  /wallet-download/wallet.zip
error: cannot find zipfile directory in ...
```

**Fix:**
- Verify wallet uploaded correctly
- Check wallet file size in bucket
- Re-download and re-upload wallet

### Issue: Database Connection Fails

**Symptoms:**
```
ORA-12154: TNS:could not resolve the connect identifier specified
```

**Fix:**
```bash
# Verify TNS_ADMIN is set
kubectl exec -n backend <pod> -- env | grep TNS_ADMIN

# Check tnsnames.ora exists
kubectl exec -n backend <pod> -- cat /opt/oracle/wallet/tnsnames.ora

# Verify TNS alias matches
# Connection string should use: stagingdb_high (not hostname)
```

## Summary

**Infrastructure Changes:**
- ✅ OCI Object Storage bucket created
- ✅ Vault IAM policy updated for bucket access
- ✅ Vault secret created with bucket metadata
- ✅ ATP mTLS enabled

**GitOps Changes:**
- ⏳ Create ExternalSecret for bucket info
- ⏳ Create ExternalSecret for wallet password
- ⏳ Update application deployments with initContainers
- ⏳ Configure ArgoCD sync waves

**Manual Steps Completed:**
- ⏳ Download ATP wallet from Console
- ⏳ Upload wallet to Object Storage
- ⏳ Create wallet password secret in Vault

---

**Next Action:** Deploy wallet bucket infrastructure with `terragrunt apply`
