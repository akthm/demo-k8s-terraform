# Always Free ATP - Public Endpoint Workaround

## Problem

Always Free Autonomous Database **does not support private endpoints**. It can only be accessed via public endpoints with IP whitelisting.

## Solution: Public Endpoint + NAT Gateway IP Whitelisting

### Architecture

```
┌─────────────────────────────────────────────────────┐
│ OKE Private Subnet (10.0.20.0/24)                   │
│                                                     │
│  ┌──────────────┐                                  │
│  │ Worker Pods  │                                  │
│  │ (flask-app,  │                                  │
│  │  keycloak)   │                                  │
│  └──────┬───────┘                                  │
│         │                                          │
│         │ Outbound to internet                     │
│         ▼                                          │
│  ┌──────────────┐                                  │
│  │ NAT Gateway  │──────────────────────┐           │
│  │ Public IP:   │                      │           │
│  │ X.X.X.X      │                      │           │
│  └──────────────┘                      │           │
└────────────────────────────────────────┼───────────┘
                                         │
                                         │ TLS/HTTPS
                                         │ Port 1522
                                         ▼
                      ┌──────────────────────────────┐
                      │ ATP Public Endpoint          │
                      │ stagingdb_high.atp.          │
                      │ il-jerusalem-1.              │
                      │ oraclecloud.com:1522         │
                      │                              │
                      │ Whitelist: NAT Gateway IP    │
                      │ (X.X.X.X/32)                 │
                      └──────────────────────────────┘
```

### Steps to Configure

#### 1. Get NAT Gateway Public IP

```bash
# From network module
cd live/oci-staging/network
terragrunt output nat_gateway_public_ip

# Or via OCI CLI
oci network nat-gateway list \
  --compartment-id $TG_VAR_oci_compartment_id \
  --vcn-id <vcn-ocid> \
  --query 'data[0]."nat-ip"' \
  --raw-output
```

#### 2. Update ATP Whitelist Configuration

```bash
# Set environment variable
export TG_VAR_nat_gateway_public_ip="<your-nat-gateway-ip>"

# Update terragrunt.hcl whitelisted_ips with NAT IP
cd live/oci-staging/atp

# Edit terragrunt.hcl:
whitelisted_ips = [
  "${nat_gateway_public_ip}/32",  # NAT Gateway IP for OKE worker outbound
  "203.0.113.5/32",                # Your office IP (for SQL*Plus access)
  "198.51.100.10/32",              # Bastion public IP (optional)
]
```

#### 3. Deploy ATP with Public Endpoint

```bash
cd live/oci-staging/atp
terragrunt apply
```

#### 4. Update Vault Secrets with Public Endpoint

```bash
# Get ATP public endpoint
ATP_HOST=$(terragrunt output -raw connection_hostname)
echo "ATP Public Endpoint: $ATP_HOST"

# Update vault secrets (via OCI Console or CLI)
# Set DB_HOST to public endpoint hostname
```

### Connection String (Public Endpoint)

```python
# Python (psycopg2)
import psycopg2

conn = psycopg2.connect(
    host="stagingdb_high.atp.il-jerusalem-1.oraclecloud.com",
    port=1522,  # Note: Public endpoints use 1522
    database="stagingdb_high",
    user="flask_user",
    password="<from-vault>",
    sslmode="require"
)
```

### Security Considerations

**Pros:**
- ✅ Works with Always Free tier
- ✅ TLS encryption in transit
- ✅ IP whitelist restricts access
- ✅ No wallet management needed
- ✅ Standard PostgreSQL/JDBC drivers

**Cons:**
- ⚠️ Database is on public internet (but IP-restricted)
- ⚠️ NAT Gateway IP is shared by all pods (no per-pod isolation)
- ⚠️ NAT Gateway IP changes if NAT Gateway is recreated

**Mitigations:**
- Enable OCI Cloud Guard for threat detection
- Use strong passwords (store in OCI Vault)
- Monitor ATP audit logs
- Restrict whitelist to minimum necessary IPs
- Consider upgrading to paid ATP for private endpoint (~$500/month)

## Alternative Solutions

### Option 2: Use Bitnami PostgreSQL Helm Chart (Recommended Alternative)

Deploy PostgreSQL inside the OKE cluster instead of using ATP:

**Pros:**
- ✅ Fully private (no public endpoint)
- ✅ No IP whitelisting needed
- ✅ Free (uses existing worker node resources)
- ✅ PostgreSQL-native (no Oracle compatibility layer)

**Cons:**
- ❌ Not managed (you handle backups, HA)
- ❌ Uses worker node storage (limited by Always Free 100GB boot volume)
- ❌ No auto-scaling or auto-tuning

**Implementation:**

```yaml
# Via ArgoCD Application manifest
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: postgresql
  namespace: argocd
spec:
  source:
    repoURL: https://charts.bitnami.com/bitnami
    chart: postgresql
    targetRevision: 13.2.1
    helm:
      values: |
        auth:
          existingSecret: postgres-admin-secret
          database: stagingdb
        primary:
          persistence:
            size: 10Gi
            storageClass: oci-bv
          resources:
            requests:
              memory: 1Gi
              cpu: 500m
        metrics:
          enabled: true
  destination:
    namespace: database
    server: https://kubernetes.default.svc
```

### Option 3: Cloud SQL Proxy Pattern

Use a sidecar proxy to connect from private pods to public ATP:

**Implementation:**
- Deploy proxy container alongside app pods
- Proxy handles connection pooling and TLS
- App connects to localhost proxy

**Not recommended** - adds complexity without significant benefit over direct connection.

### Option 4: Upgrade to Paid ATP

**Cost:** ~$500/month for 1 OCPU private endpoint ATP  
**Benefit:** Full VCN integration, private endpoint, auto-scaling

Only worth it for production workloads with compliance requirements.

## Recommendation

**For Development/Staging:**
- Use **Option 1** (Public ATP + IP whitelist) - Most practical
- Or use **Option 2** (Bitnami PostgreSQL) - Most secure and free

**For Production:**
- Upgrade to **paid ATP with private endpoint**
- Or use managed PostgreSQL on another cloud provider

## Current Configuration

The ATP module now supports both:
- **Always Free**: Public endpoint with IP whitelisting
- **Paid**: Private endpoint in VCN

Set `is_free_tier = true` for public endpoint mode.

## Security Hardening for Public Endpoint

```bash
# 1. Rotate passwords regularly
oci vault secret update --secret-id <secret-ocid> ...

# 2. Enable audit logging
# Via OCI Console → ATP → Settings → Audit → Enable

# 3. Monitor access logs
# Via OCI Console → ATP → Logs → Audit Logs

# 4. Restrict whitelist to minimum IPs
whitelisted_ips = [
  "${nat_gateway_ip}/32",  # ONLY NAT Gateway
]

# 5. Use strong passwords (20+ chars, random)
export TG_VAR_atp_admin_password="$(openssl rand -base64 32)"
```

## Troubleshooting

### Connection Timeout

```bash
# Verify NAT Gateway IP is whitelisted
terragrunt output whitelisted_ips

# Test from worker node (exec into any pod)
kubectl run -it --rm test --image=postgres:14 -- bash
psql "host=stagingdb_high.atp.il-jerusalem-1.oraclecloud.com port=1522 dbname=stagingdb_high user=flask_user sslmode=require"
```

### Access Denied

```bash
# Check whitelist includes your NAT Gateway IP
cd live/oci-staging/network
NAT_IP=$(terragrunt output -raw nat_gateway_public_ip)

cd ../atp
grep $NAT_IP terragrunt.hcl
```

### Port Issues

- **Private endpoint**: Port 1521
- **Public endpoint**: Port 1522 (different!)

Make sure your connection strings use the correct port for public endpoints.
