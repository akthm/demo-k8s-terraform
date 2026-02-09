# Disaster Recovery Runbook

This document defines the disaster recovery (DR) procedures, recovery targets, and runbooks for the OCI OKE infrastructure.

## Table of Contents

1. [Recovery Objectives](#recovery-objectives)
2. [Component Recovery Matrix](#component-recovery-matrix)
3. [Backup Strategy](#backup-strategy)
4. [Recovery Procedures](#recovery-procedures)
5. [DR Testing Schedule](#dr-testing-schedule)
6. [Escalation Contacts](#escalation-contacts)

---

## Recovery Objectives

### Definitions

| Term | Definition |
|------|------------|
| **RTO** (Recovery Time Objective) | Maximum acceptable time to restore service after an incident |
| **RPO** (Recovery Point Objective) | Maximum acceptable data loss measured in time |
| **MTTR** (Mean Time To Recovery) | Average time to restore service |

### Production Tier Targets

| Service | RTO | RPO | MTTR Target |
|---------|-----|-----|-------------|
| **Kubernetes API** | 15 minutes | 0 (stateless) | 10 minutes |
| **Application Workloads** | 30 minutes | 0 (GitOps) | 20 minutes |
| **ATP Database** | 1 hour | 5 minutes | 45 minutes |
| **OCI Vault Secrets** | 30 minutes | 24 hours | 20 minutes |
| **Ingress/Load Balancer** | 15 minutes | 0 (stateless) | 10 minutes |
| **Monitoring Stack** | 1 hour | 1 hour | 45 minutes |

### Service Tiers

| Tier | Description | RTO | RPO |
|------|-------------|-----|-----|
| **Tier 1 - Critical** | Database, Kubernetes API | ≤15 min | ≤5 min |
| **Tier 2 - Essential** | Application workloads, secrets | ≤30 min | ≤1 hour |
| **Tier 3 - Standard** | Monitoring, logging | ≤2 hours | ≤4 hours |

---

## Component Recovery Matrix

### Infrastructure Components

| Component | Backup Method | Backup Frequency | Retention | Recovery Method |
|-----------|---------------|------------------|-----------|-----------------|
| **VCN/Network** | Terraform state | On change | Indefinite | Terragrunt apply |
| **OKE Cluster** | Terraform state | On change | Indefinite | Terragrunt apply |
| **Node Pool** | Terraform state | On change | Indefinite | Terragrunt apply |
| **ATP Database** | OCI Automatic Backup | Daily + continuous | 60 days | Point-in-time restore |
| **OCI Vault** | Secret versioning | On change | 30 versions | Version restore |
| **Terraform State** | S3 + DynamoDB | On change | Versioned | S3 version restore |

### Kubernetes Resources

| Resource Type | Backup Method | Recovery Method |
|---------------|---------------|-----------------|
| **Deployments/Services** | GitOps (ArgoCD) | ArgoCD sync from Git |
| **ConfigMaps** | GitOps (ArgoCD) | ArgoCD sync from Git |
| **Secrets** | ESO → OCI Vault | ESO sync from Vault |
| **PVCs/PVs** | OCI Block Volume Backup | Restore from backup |
| **CRDs** | GitOps (ArgoCD) | ArgoCD sync from Git |

---

## Backup Strategy

### 1. ATP Database Backups

OCI Autonomous Database provides automatic backups with the following configuration:

```hcl
# Configured in modules/oci-atp/main.tf
is_auto_scaling_enabled           = true
is_auto_scaling_for_storage_enabled = true
# Automatic backups: Enabled by default
# Retention: 60 days
# Point-in-time recovery: Enabled
```

**Backup Types**:
- **Full Backup**: Weekly (Sunday 02:00 UTC)
- **Incremental Backup**: Daily
- **Archive Logs**: Continuous (5-minute RPO)

**Cross-Region Backup** (Production):
```bash
# Enable Autonomous Data Guard for cross-region DR
oci db autonomous-database create-cross-region-data-guard-details \
  --source-id <primary-atp-ocid> \
  --region <dr-region>
```

### 2. Terraform State Backups

State files are stored in S3 with versioning enabled:

```hcl
# Configured in root.hcl
remote_state {
  backend = "s3"
  config = {
    bucket         = "terraform-state-bucket"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

**Recovery**: Use S3 versioning to restore previous state versions.

### 3. OCI Vault Secret Versioning

Secrets in OCI Vault maintain version history:

```bash
# List secret versions
oci vault secret list-secret-versions --secret-id <secret-ocid>

# Restore specific version
oci vault secret update-secret-content \
  --secret-id <secret-ocid> \
  --secret-content-content <base64-content>
```

### 4. Kubernetes Workload Backups

All Kubernetes resources are managed via GitOps:

- **Source of Truth**: Git repository (ArgoCD app-of-apps)
- **Backup**: Git repository with branch protection
- **Recovery**: ArgoCD sync or `kubectl apply -f`

---

## Recovery Procedures

### Scenario 1: OKE Cluster Failure

**Symptoms**: kubectl commands fail, API server unreachable

**Recovery Steps**:

```bash
# 1. Verify cluster status in OCI Console
oci ce cluster get --cluster-id <cluster-ocid>

# 2. If cluster is in FAILED state, recreate via Terragrunt
cd live/oci-staging/cluster
terragrunt destroy  # If needed
terragrunt apply

# 3. Recreate node pool
cd ../nodepool
terragrunt apply

# 4. Re-establish bastion tunnel
./scripts/oci-bastion-kube-tunnel.sh

# 5. Verify cluster health
kubectl get nodes
kubectl get pods -A

# 6. ArgoCD will automatically sync workloads
# Verify sync status
argocd app list
argocd app sync <app-name>
```

**Estimated Time**: 15-20 minutes

---

### Scenario 2: ATP Database Failure/Corruption

**Symptoms**: Application database errors, connection failures

**Recovery Steps**:

```bash
# 1. Check ATP status
oci db autonomous-database get --autonomous-database-id <atp-ocid>

# 2. Point-in-time recovery (last known good state)
oci db autonomous-database restore \
  --autonomous-database-id <atp-ocid> \
  --timestamp "2026-02-07T10:00:00Z"

# 3. Monitor restore progress
oci db autonomous-database get --autonomous-database-id <atp-ocid> \
  --query 'data."lifecycle-state"'

# 4. Verify connectivity
# From a pod in the cluster:
kubectl run db-test --rm -it --image=postgres:15 -- \
  psql "host=<atp-endpoint> port=1521 dbname=STAGINGDB_HIGH user=ADMIN sslmode=require"

# 5. Validate application functionality
kubectl rollout restart deployment/<app-name> -n <namespace>
```

**Estimated Time**: 45-60 minutes

---

### Scenario 3: OCI Vault Key/Secret Loss

**Symptoms**: ESO sync failures, missing Kubernetes secrets

**Recovery Steps**:

```bash
# 1. Check vault status
oci kms management vault get --vault-id <vault-ocid>

# 2. List available secret versions
oci vault secret list-secret-versions --secret-id <secret-ocid>

# 3. Restore from previous version
# Get content from previous version
VERSION_NUMBER=2
CONTENT=$(oci vault secret-bundle get \
  --secret-id <secret-ocid> \
  --version-number $VERSION_NUMBER \
  --query 'data."secret-bundle-content".content' \
  --raw-output)

# Update secret with previous content
oci vault secret update-secret-content \
  --secret-id <secret-ocid> \
  --secret-content-content "$CONTENT"

# 4. Force ESO to resync
kubectl annotate externalsecret <name> force-sync=$(date +%s) --overwrite -n <namespace>

# 5. Verify secrets are restored
kubectl get secrets -n <namespace>
```

**If vault/key is completely lost**:

```bash
# Recreate vault infrastructure
cd live/oci-staging/vault
terragrunt destroy
terragrunt apply

# Manually recreate secrets from backup documentation or password manager
# Then update cluster-services to point to new vault
cd ../cluster-services
terragrunt apply
```

**Estimated Time**: 20-30 minutes (version restore) / 60+ minutes (full recreate)

---

### Scenario 4: Node Pool Failure

**Symptoms**: Pods in Pending state, node NotReady, capacity issues

**Recovery Steps**:

```bash
# 1. Check node status
kubectl get nodes
kubectl describe node <node-name>

# 2. Check node pool status in OCI
oci ce node-pool get --node-pool-id <nodepool-ocid>

# 3. If nodes are unhealthy, trigger replacement
oci ce node-pool update \
  --node-pool-id <nodepool-ocid> \
  --size <current-size>  # Forces node cycling

# 4. If node pool is corrupted, recreate
cd live/oci-staging/nodepool
terragrunt destroy
terragrunt apply

# 5. Wait for nodes to join cluster
kubectl get nodes -w

# 6. Verify workloads reschedule
kubectl get pods -A | grep -v Running
```

**Estimated Time**: 10-15 minutes

---

### Scenario 5: Bastion Service Unavailable

**Symptoms**: Cannot establish SSH tunnel, kubectl access fails

**Recovery Steps**:

```bash
# 1. Check bastion status
oci bastion bastion get --bastion-id <bastion-ocid>

# 2. If bastion is in FAILED state, recreate
cd live/oci-staging/bastion
terragrunt destroy
terragrunt apply

# 3. Update bastion OCID in environment
export BASTION_OCID=$(terragrunt output -raw bastion_id)

# 4. Establish new tunnel
./scripts/oci-bastion-kube-tunnel.sh

# Alternative: Enable public K8s API temporarily (emergency only)
oci ce cluster update \
  --cluster-id <cluster-ocid> \
  --endpoint-config '{"isPublicIpEnabled": true}'
```

**Estimated Time**: 10-15 minutes

---

### Scenario 6: Complete Environment Rebuild

**Symptoms**: Catastrophic failure requiring full environment rebuild

**Recovery Steps**:

```bash
# 1. Ensure Terraform state is accessible
cd live/oci-staging
terragrunt run-all init

# 2. Deploy in dependency order
cd network && terragrunt apply
cd ../cluster && terragrunt apply
cd ../nodepool && terragrunt apply
cd ../bastion && terragrunt apply
cd ../vault && terragrunt apply
cd ../atp && terragrunt apply
cd ../edge-proxy && terragrunt apply
cd ../load-balancer && terragrunt apply
cd ../cluster-services && terragrunt apply

# 3. Establish bastion tunnel
./scripts/oci-bastion-kube-tunnel.sh

# 4. Restore ATP from backup (if needed)
oci db autonomous-database restore \
  --autonomous-database-id <atp-ocid> \
  --timestamp <last-backup-timestamp>

# 5. Verify ArgoCD syncs all applications
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
argocd login localhost:8080
argocd app sync --all

# 6. Validate all services
kubectl get pods -A
kubectl get svc -A
```

**Estimated Time**: 60-90 minutes

---

## Disaster Recovery Testing

### Testing Schedule

| Test Type | Frequency | Duration | Owner |
|-----------|-----------|----------|-------|
| **ATP Point-in-Time Recovery** | Monthly | 2 hours | DBA Team |
| **Node Pool Failover** | Monthly | 1 hour | Platform Team |
| **Bastion Tunnel Recreation** | Weekly | 30 min | Platform Team |
| **Full Environment Rebuild** | Quarterly | 4 hours | Platform Team |
| **ArgoCD Sync Recovery** | Monthly | 1 hour | DevOps Team |

### Test Checklist

#### Monthly DR Test

- [ ] Trigger ATP point-in-time recovery to test database
- [ ] Drain and delete one worker node, verify recovery
- [ ] Delete and recreate bastion session
- [ ] Force ArgoCD resync of all applications
- [ ] Verify monitoring alerts fire correctly
- [ ] Document any issues and update runbooks

#### Quarterly Full DR Test

- [ ] Destroy and recreate entire environment in DR region
- [ ] Restore ATP from cross-region backup
- [ ] Validate all applications functional
- [ ] Measure actual RTO/RPO against targets
- [ ] Update DR documentation based on findings

---

## Cross-Region Disaster Recovery

### Production DR Architecture

```
┌─────────────────────────┐         ┌─────────────────────────┐
│  Primary Region         │         │  DR Region              │
│  (il-jerusalem-1)       │         │  (eu-frankfurt-1)       │
│                         │         │                         │
│  ┌───────────────────┐  │         │  ┌───────────────────┐  │
│  │ OKE Cluster       │  │         │  │ OKE Cluster       │  │
│  │ (Active)          │  │         │  │ (Standby)         │  │
│  └───────────────────┘  │         │  └───────────────────┘  │
│           │             │         │           │             │
│  ┌────────▼──────────┐  │  Sync   │  ┌────────▼──────────┐  │
│  │ ATP Primary       │◄─┼─────────┼─►│ ATP Standby       │  │
│  │ (Data Guard)      │  │         │  │ (Data Guard)      │  │
│  └───────────────────┘  │         │  └───────────────────┘  │
│                         │         │                         │
│  ┌───────────────────┐  │  Sync   │  ┌───────────────────┐  │
│  │ OCI Vault         │◄─┼─────────┼─►│ OCI Vault (Copy)  │  │
│  └───────────────────┘  │         │  └───────────────────┘  │
└─────────────────────────┘         └─────────────────────────┘
```

### Failover Procedure

```bash
# 1. Activate DR region infrastructure
cd live/oci-dr/
terragrunt run-all apply

# 2. Perform ATP switchover
oci db autonomous-database switchover \
  --autonomous-database-id <standby-atp-ocid>

# 3. Update DNS to point to DR load balancer
# (Via Cloudflare API or OCI DNS)

# 4. Verify DR environment
kubectl --kubeconfig=kubeconfig.dr get nodes
kubectl --kubeconfig=kubeconfig.dr get pods -A
```

---

## Escalation Contacts

| Role | Contact | Escalation Time |
|------|---------|-----------------|
| **On-Call Engineer** | PagerDuty Rotation | Immediate |
| **Platform Lead** | [Name] | 15 minutes |
| **Database Admin** | [Name] | 30 minutes |
| **Security Team** | [Name] | If security incident |
| **OCI Support** | Oracle Support Portal | After internal escalation |

### Escalation Matrix

| Severity | Description | Response Time | Escalation |
|----------|-------------|---------------|------------|
| **SEV-1** | Complete outage | 15 minutes | Immediate to Platform Lead |
| **SEV-2** | Major degradation | 30 minutes | 1 hour to Platform Lead |
| **SEV-3** | Minor degradation | 2 hours | Next business day |
| **SEV-4** | Informational | Next business day | N/A |

---

## Appendix: Useful Commands

### Quick Health Checks

```bash
# Cluster health
kubectl get nodes
kubectl get pods -A | grep -v Running
kubectl top nodes

# ATP status
oci db autonomous-database get --autonomous-database-id <ocid> \
  --query 'data.{State:"lifecycle-state",CPU:"cpu-core-count",Storage:"data-storage-size-in-tbs"}'

# Vault status
oci kms management vault get --vault-id <ocid> \
  --query 'data.{State:"lifecycle-state",Type:"vault-type"}'

# Bastion status
oci bastion bastion get --bastion-id <ocid> \
  --query 'data.{State:"lifecycle-state",TargetSubnet:"target-subnet-id"}'
```

### Backup Status Verification

```bash
# ATP last backup
oci db autonomous-database-backup list \
  --autonomous-database-id <ocid> \
  --sort-by TIMECREATED \
  --sort-order DESC \
  --limit 5

# Terraform state versions
aws s3api list-object-versions \
  --bucket terraform-state-bucket \
  --prefix "live/oci-staging" \
  --max-items 10
```

---

*Last Updated: February 2026*
*Document Owner: Platform Engineering Team*
*Review Cycle: Quarterly*
