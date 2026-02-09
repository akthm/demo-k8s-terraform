# Production Operations Runbook

This document provides operational procedures for day-2 operations, incident response, and maintenance of the OCI OKE infrastructure.

## Table of Contents

1. [Monitoring Prerequisites](#monitoring-prerequisites)
2. [Daily Operations](#daily-operations)
3. [Incident Response](#incident-response)
4. [Common Troubleshooting](#common-troubleshooting)
5. [Maintenance Procedures](#maintenance-procedures)
6. [Capacity Management](#capacity-management)
7. [Security Operations](#security-operations)

---

## Monitoring Prerequisites

### Required: External Monitoring Stack

The monitoring stack is **deployed separately via ArgoCD** from the application repository. This infrastructure repository assumes monitoring is already operational.

**Required Components**:

| Component | Namespace | Purpose |
|-----------|-----------|---------|
| Prometheus | `monitoring` | Metrics collection, alerting rules |
| Grafana | `monitoring` | Dashboards, visualization |
| Alertmanager | `monitoring` | Alert routing, notifications |
| Loki | `monitoring` | Log aggregation |
| kube-state-metrics | `monitoring` | Kubernetes object metrics |

### Verification

Before performing SLO tracking or incident response:

```bash
# Verify monitoring stack is deployed
kubectl get pods -n monitoring

# Expected output:
# prometheus-server-xxx          Running
# grafana-xxx                    Running
# alertmanager-xxx               Running
# loki-xxx                       Running
# kube-state-metrics-xxx         Running

# Verify Prometheus is scraping targets
kubectl port-forward -n monitoring svc/prometheus-server 9090:80 &
curl -s localhost:9090/api/v1/targets | jq '.data.activeTargets | length'
```

### Integration Points

The infrastructure provides these integration points for monitoring:

| Resource | Metric Source | How to Scrape |
|----------|---------------|---------------|
| OKE Nodes | kubelet, node-exporter | ServiceMonitor |
| Ingress Controller | NGINX metrics | ServiceMonitor on ingress-nginx |
| External Secrets | ESO metrics endpoint | ServiceMonitor on external-secrets |
| ATP Database | OCI Metrics API | Prometheus OCI SD or manual |

---

## Daily Operations

### Morning Health Check

Run these checks at the start of each day:

```bash
#!/bin/bash
# daily-health-check.sh

echo "=== OKE Cluster Health Check ==="
echo ""

# 1. Node status
echo "📦 Node Status:"
kubectl get nodes -o wide
echo ""

# 2. Pod health (non-running pods)
echo "⚠️  Pods not running:"
kubectl get pods -A | grep -v Running | grep -v Completed
echo ""

# 3. Resource utilization
echo "📊 Resource Utilization:"
kubectl top nodes
echo ""

# 4. Recent events (warnings/errors)
echo "🔔 Recent Warnings (last 1 hour):"
kubectl get events -A --sort-by='.lastTimestamp' | grep -E 'Warning|Error' | tail -20
echo ""

# 5. PVC status
echo "💾 PVC Status:"
kubectl get pvc -A | grep -v Bound
echo ""

# 6. Certificate expiry (if cert-manager deployed)
echo "🔐 Certificates expiring within 30 days:"
kubectl get certificates -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}: {.status.notAfter}{"\n"}{end}' 2>/dev/null || echo "cert-manager not found"
echo ""

# 7. ArgoCD sync status
echo "🔄 ArgoCD Application Status:"
kubectl get applications -n argocd -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status' 2>/dev/null || echo "ArgoCD not accessible"
echo ""

echo "=== Health Check Complete ==="
```

### Daily Checklist

- [ ] Review Grafana dashboards for anomalies
- [ ] Check Alertmanager for suppressed/silenced alerts
- [ ] Verify ArgoCD applications are synced
- [ ] Review ATP database metrics (storage, connections)
- [ ] Check bastion session status (if persistent tunnel)

---

## Incident Response

### Severity Levels

| Level | Description | Response Time | Examples |
|-------|-------------|---------------|----------|
| **SEV-1** | Complete outage | 15 min | K8s API down, all apps unavailable |
| **SEV-2** | Major degradation | 30 min | >50% error rate, database unavailable |
| **SEV-3** | Minor degradation | 2 hours | Single service affected, slow performance |
| **SEV-4** | Low impact | Next business day | Cosmetic issues, non-critical alerts |

### Incident Response Workflow

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   DETECT    │───►│   TRIAGE    │───►│   RESPOND   │───►│   RESOLVE   │
│             │    │             │    │             │    │             │
│ • Alert     │    │ • Severity  │    │ • Mitigate  │    │ • Fix root  │
│ • Monitor   │    │ • Impact    │    │ • Communicate│   │ • Verify    │
│ • Customer  │    │ • Assign    │    │ • Escalate  │    │ • Document  │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
                                                                │
                                                                ▼
                                                        ┌─────────────┐
                                                        │ POST-MORTEM │
                                                        │             │
                                                        │ • Timeline  │
                                                        │ • RCA       │
                                                        │ • Actions   │
                                                        └─────────────┘
```

### Incident Commander Checklist

#### On Incident Declaration:

- [ ] Acknowledge alert in PagerDuty/Alertmanager
- [ ] Create incident channel (e.g., #inc-YYYYMMDD-description)
- [ ] Assign roles: IC, Scribe, Communications
- [ ] Update status page (if customer-facing)

#### During Incident:

- [ ] Maintain timeline of events and actions
- [ ] Coordinate responders, avoid duplicate work
- [ ] Provide regular updates (every 30 min for SEV-1/2)
- [ ] Escalate if needed (see escalation matrix)

#### Post-Incident:

- [ ] Declare incident resolved
- [ ] Update status page to resolved
- [ ] Schedule post-mortem (within 48 hours for SEV-1/2)
- [ ] Create action items and assign owners

### Communication Templates

#### Status Page Update (Investigating)

```
Title: [Service] Degradation Detected

We are investigating reports of [brief description].

Impact: [Affected services/users]
Status: Investigating
Started: [Timestamp]

We will provide updates every 30 minutes.
```

#### Status Page Update (Resolved)

```
Title: [Service] Issue Resolved

The issue affecting [service] has been resolved.

Root Cause: [Brief description]
Duration: [Start time] - [End time]
Impact: [Summary of impact]

A detailed post-mortem will be published within 48 hours.
```

---

## Common Troubleshooting

### Kubernetes API Unreachable

**Symptoms**: `kubectl` commands fail, timeout errors

```bash
# 1. Check bastion tunnel status
lsof -i:6443
ps aux | grep "ssh.*6443"

# 2. Recreate tunnel if needed
pkill -f "ssh.*6443"
./scripts/oci-bastion-kube-tunnel.sh

# 3. Verify OKE cluster status via OCI CLI
oci ce cluster get --cluster-id $CLUSTER_ID --query 'data."lifecycle-state"'

# 4. Check OCI Console for cluster events
# Navigate: Developer Services > Kubernetes Clusters > [cluster] > Events
```

### Pods Stuck in Pending

**Symptoms**: Pods remain in Pending state

```bash
# 1. Check pod events
kubectl describe pod <pod-name> -n <namespace>

# 2. Common causes and solutions:

# Insufficient resources
kubectl top nodes
kubectl describe nodes | grep -A 5 "Allocated resources"

# PVC not bound
kubectl get pvc -n <namespace>
kubectl describe pvc <pvc-name> -n <namespace>

# Node affinity/taints
kubectl get nodes --show-labels
kubectl describe nodes | grep -A 5 Taints

# 3. If nodes at capacity, scale node pool
oci ce node-pool update \
  --node-pool-id $NODEPOOL_ID \
  --size 3  # Increase node count
```

### ATP Database Connection Failures

**Symptoms**: Application logs show database connection errors

```bash
# 1. Check ATP status
oci db autonomous-database get \
  --autonomous-database-id $ATP_ID \
  --query 'data.{State:"lifecycle-state",Available:"is-free-tier"}'

# 2. Verify network connectivity from pod
kubectl run db-debug --rm -it --image=busybox -- sh
# Inside pod:
nc -zv <atp-private-ip> 1521

# 3. Check security list rules
oci network security-list get --security-list-id $WORKER_SL_ID \
  --query 'data."egress-security-rules"'

# 4. Verify ATP NSG allows worker subnet
oci network nsg get --network-security-group-id $ATP_NSG_ID

# 5. Test connection with credentials
kubectl run pg-test --rm -it --image=postgres:15 -- \
  psql "host=<atp-endpoint> port=1521 dbname=STAGINGDB_HIGH user=ADMIN sslmode=require"
```

### External Secrets Not Syncing

**Symptoms**: Kubernetes secrets missing or outdated

```bash
# 1. Check ExternalSecret status
kubectl get externalsecret -A
kubectl describe externalsecret <name> -n <namespace>

# 2. Check ClusterSecretStore status
kubectl get clustersecretstore
kubectl describe clustersecretstore oci-vault

# 3. Verify OCI Vault secret exists
oci vault secret get --secret-id $SECRET_ID

# 4. Check ESO operator logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets

# 5. Force resync
kubectl annotate externalsecret <name> force-sync=$(date +%s) --overwrite -n <namespace>

# 6. Verify instance principal authentication
# On worker node (via SSH or OCI Console):
curl -H "Authorization: Bearer Oracle" http://169.254.169.254/opc/v2/instance/
```

### High Memory/CPU on Nodes

**Symptoms**: Resource pressure, OOMKilled pods

```bash
# 1. Check current utilization
kubectl top nodes
kubectl top pods -A --sort-by=memory

# 2. Identify resource-heavy pods
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} Memory: {.spec.containers[0].resources.requests.memory}{"\n"}{end}'

# 3. Check for memory leaks (pods with increasing memory)
kubectl top pods -n <namespace> --containers

# 4. Evict non-critical pods if needed
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# 5. Scale up node pool
oci ce node-pool update --node-pool-id $NODEPOOL_ID --size 4
```

### Ingress Not Routing Traffic

**Symptoms**: 502/504 errors, connection refused

```bash
# 1. Check ingress controller pods
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx

# 2. Check ingress resources
kubectl get ingress -A
kubectl describe ingress <name> -n <namespace>

# 3. Verify backend service
kubectl get svc -n <namespace>
kubectl get endpoints -n <namespace>

# 4. Check Network Load Balancer health
oci nlb network-load-balancer-health get \
  --network-load-balancer-id $NLB_ID

# 5. Check backend set health
oci nlb backend-set-health get \
  --network-load-balancer-id $NLB_ID \
  --backend-set-name <backend-set-name>
```

---

## Maintenance Procedures

### Scheduled Maintenance Window

**Standard Window**: Sundays 02:00-06:00 UTC

#### Pre-Maintenance Checklist

- [ ] Notify stakeholders 7 days in advance (SLA requirement)
- [ ] Update status page with maintenance schedule
- [ ] Verify backups are current
- [ ] Prepare rollback procedures
- [ ] Confirm on-call coverage during window

### Node Pool Updates

```bash
# 1. Check current node pool configuration
oci ce node-pool get --node-pool-id $NODEPOOL_ID

# 2. Drain nodes one at a time
for node in $(kubectl get nodes -o name); do
  echo "Draining $node..."
  kubectl drain $node --ignore-daemonsets --delete-emptydir-data
  
  # Wait for workloads to reschedule
  sleep 60
  
  # Cordon back and allow scheduling
  kubectl uncordon $node
done

# 3. Trigger node replacement (for image updates)
oci ce node-pool update \
  --node-pool-id $NODEPOOL_ID \
  --node-image-id <new-image-ocid>
```

### OKE Cluster Upgrades

```bash
# 1. Check available versions
oci ce cluster-options get \
  --cluster-option-id all \
  --query 'data."kubernetes-versions"'

# 2. Review upgrade notes
# https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengaboutupgrades.htm

# 3. Upgrade control plane
oci ce cluster update \
  --cluster-id $CLUSTER_ID \
  --kubernetes-version v1.29.1

# 4. Wait for control plane upgrade
watch "oci ce cluster get --cluster-id $CLUSTER_ID --query 'data.\"lifecycle-state\"'"

# 5. Upgrade node pool
oci ce node-pool update \
  --node-pool-id $NODEPOOL_ID \
  --kubernetes-version v1.29.1

# 6. Verify cluster health
kubectl get nodes
kubectl get pods -A
```

### ATP Maintenance

ATP maintenance is managed by Oracle. To check maintenance schedule:

```bash
# Check upcoming maintenance
oci db autonomous-database get \
  --autonomous-database-id $ATP_ID \
  --query 'data.{MaintenanceWindow:"maintenance-schedule-type",NextMaintenance:"time-maintenance-begin"}'

# View maintenance history
oci db autonomous-database list-autonomous-database-maintenance-history \
  --autonomous-database-id $ATP_ID
```

### Certificate Renewal

If using cert-manager with Let's Encrypt:

```bash
# Check certificate status
kubectl get certificates -A

# Check upcoming expirations
kubectl get certificates -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}: expires {.status.notAfter}{"\n"}{end}'

# Force renewal (if needed)
kubectl delete secret <tls-secret-name> -n <namespace>
# cert-manager will automatically request new certificate
```

---

## Capacity Management

### Current Capacity

```bash
# Node capacity
kubectl describe nodes | grep -A 10 "Capacity:"

# Current allocation
kubectl describe nodes | grep -A 10 "Allocated resources:"

# Cluster-wide utilization
kubectl top nodes
```

### Scaling Thresholds

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| CPU Utilization | 70% | 85% | Scale nodes |
| Memory Utilization | 75% | 90% | Scale nodes |
| ATP Storage | 75% | 90% | Enable auto-scaling |
| ATP Connections | 80% | 95% | Review connection pooling |
| PVC Usage | 75% | 90% | Expand PVC |

### Horizontal Scaling

```bash
# Scale node pool
oci ce node-pool update \
  --node-pool-id $NODEPOOL_ID \
  --size <new-size>

# Monitor scaling progress
watch kubectl get nodes
```

### Vertical Scaling

```bash
# Update node shape (requires node pool recreation)
# In Terragrunt:
cd live/oci-staging/nodepool

# Edit terragrunt.hcl to update shape
# Then apply
terragrunt apply
```

### ATP Scaling

```bash
# Enable auto-scaling (recommended)
oci db autonomous-database update \
  --autonomous-database-id $ATP_ID \
  --is-auto-scaling-enabled true

# Manual scaling
oci db autonomous-database update \
  --autonomous-database-id $ATP_ID \
  --cpu-core-count 4 \
  --data-storage-size-in-tbs 2
```

---

## Security Operations

### Access Review (Monthly)

```bash
# List IAM policies
oci iam policy list --compartment-id $COMPARTMENT_ID

# List dynamic groups
oci iam dynamic-group list --compartment-id $TENANCY_ID

# Review Kubernetes RBAC
kubectl get clusterrolebindings -o wide
kubectl get rolebindings -A -o wide

# Check service accounts
kubectl get serviceaccounts -A
```

### Secret Rotation

```bash
# 1. Update secret in OCI Vault
oci vault secret create-base64 \
  --compartment-id $COMPARTMENT_ID \
  --vault-id $VAULT_ID \
  --secret-name <secret-name>-v2 \
  --secret-content-content $(echo -n '{"key":"new-value"}' | base64)

# 2. Update ESO to reference new secret version
# Or rely on automatic refresh (default 1 hour)

# 3. Force immediate sync
kubectl annotate externalsecret <name> force-sync=$(date +%s) --overwrite -n <namespace>

# 4. Restart affected applications
kubectl rollout restart deployment/<app-name> -n <namespace>
```

### Security Scanning

```bash
# Scan running images (if Trivy installed)
kubectl get pods -A -o jsonpath='{range .items[*]}{.spec.containers[*].image}{"\n"}{end}' | sort -u | while read img; do
  echo "Scanning: $img"
  trivy image --severity HIGH,CRITICAL "$img"
done

# Check for privileged containers
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}: privileged={.spec.containers[*].securityContext.privileged}{"\n"}{end}' | grep true

# Check for hostNetwork pods
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}: hostNetwork={.spec.hostNetwork}{"\n"}{end}' | grep true
```

### Audit Log Review

```bash
# OCI Audit logs
oci audit event list \
  --compartment-id $COMPARTMENT_ID \
  --start-time $(date -d '24 hours ago' --utc +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date --utc +%Y-%m-%dT%H:%M:%SZ)

# Filter for specific events
oci audit event list \
  --compartment-id $COMPARTMENT_ID \
  --start-time $(date -d '24 hours ago' --utc +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date --utc +%Y-%m-%dT%H:%M:%SZ) \
  --query "data[?contains(\"event-type\", 'Delete')]"
```

---

## Runbook Maintenance

### Document Review Schedule

| Document | Review Frequency | Owner |
|----------|------------------|-------|
| This Runbook | Monthly | Platform Team |
| DR Procedures | Quarterly | Platform Team |
| SLI/SLO Definitions | Quarterly | Platform + Product |
| Security Procedures | Monthly | Security Team |

### Updating Procedures

1. Create PR with proposed changes
2. Test procedures in non-production environment
3. Get review from at least 2 team members
4. Update version history in document
5. Announce changes in team channel

---

*Last Updated: February 2026*
*Document Owner: Platform Engineering Team*
*Review Cycle: Monthly*
