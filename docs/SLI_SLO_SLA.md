# Service Level Indicators, Objectives, and Agreements

This document defines the SLI/SLO/SLA framework for the OCI OKE infrastructure platform.

## Table of Contents

1. [Definitions](#definitions)
2. [Service Level Indicators (SLIs)](#service-level-indicators-slis)
3. [Service Level Objectives (SLOs)](#service-level-objectives-slos)
4. [Service Level Agreement (SLA)](#service-level-agreement-sla)
5. [Error Budgets](#error-budgets)
6. [Monitoring Prerequisites](#monitoring-prerequisites)
7. [Escalation and Breach Response](#escalation-and-breach-response)

---

## Definitions

| Term | Definition |
|------|------------|
| **SLI** (Service Level Indicator) | A quantitative measure of service behavior (e.g., latency, availability) |
| **SLO** (Service Level Objective) | A target value or range for an SLI (e.g., 99.9% availability) |
| **SLA** (Service Level Agreement) | A contractual commitment with consequences for missing SLOs |
| **Error Budget** | The allowed amount of unreliability (100% - SLO) |
| **Burn Rate** | The rate at which error budget is being consumed |

---

## Service Level Indicators (SLIs)

### Platform Services

#### 1. Kubernetes API Availability

| Property | Value |
|----------|-------|
| **Description** | Percentage of successful K8s API requests |
| **Measurement** | `(successful_requests / total_requests) × 100` |
| **Good Event** | API request returns 2xx, 3xx, 4xx (client errors excluded from SLI) |
| **Bad Event** | API request returns 5xx or times out (>30s) |
| **Data Source** | OKE control plane metrics / kube-apiserver metrics |
| **Window** | Rolling 30 days |

```promql
# Prometheus query for K8s API availability
sum(rate(apiserver_request_total{code!~"5.."}[5m])) 
/ 
sum(rate(apiserver_request_total[5m])) * 100
```

#### 2. Kubernetes API Latency

| Property | Value |
|----------|-------|
| **Description** | Response time for K8s API requests |
| **Measurement** | Request latency percentiles (p50, p95, p99) |
| **Good Event** | Request completes within threshold |
| **Bad Event** | Request exceeds threshold |
| **Data Source** | apiserver_request_duration_seconds histogram |
| **Window** | Rolling 30 days |

```promql
# P95 latency for K8s API
histogram_quantile(0.95, 
  sum(rate(apiserver_request_duration_seconds_bucket{verb!="WATCH"}[5m])) by (le)
)
```

#### 3. Node Availability

| Property | Value |
|----------|-------|
| **Description** | Percentage of time nodes are in Ready state |
| **Measurement** | `(ready_node_minutes / total_node_minutes) × 100` |
| **Good Event** | Node status is Ready |
| **Bad Event** | Node status is NotReady, Unknown |
| **Data Source** | kube_node_status_condition metric |
| **Window** | Rolling 30 days |

```promql
# Node availability percentage
avg(kube_node_status_condition{condition="Ready", status="true"}) * 100
```

### Application Services

#### 4. Ingress Availability

| Property | Value |
|----------|-------|
| **Description** | Percentage of successful requests through ingress |
| **Measurement** | `(non_5xx_responses / total_responses) × 100` |
| **Good Event** | Response status < 500 |
| **Bad Event** | Response status >= 500 or connection refused |
| **Data Source** | NGINX ingress metrics |
| **Window** | Rolling 30 days |

```promql
# Ingress availability
sum(rate(nginx_ingress_controller_requests{status!~"5.."}[5m])) 
/ 
sum(rate(nginx_ingress_controller_requests[5m])) * 100
```

#### 5. Ingress Latency

| Property | Value |
|----------|-------|
| **Description** | Response time through ingress layer |
| **Measurement** | Request latency percentiles |
| **Good Event** | p95 latency < threshold |
| **Data Source** | nginx_ingress_controller_request_duration_seconds |
| **Window** | Rolling 30 days |

```promql
# P95 ingress latency
histogram_quantile(0.95, 
  sum(rate(nginx_ingress_controller_request_duration_seconds_bucket[5m])) by (le)
)
```

### Database Services

#### 6. ATP Database Availability

| Property | Value |
|----------|-------|
| **Description** | Database accessibility and responsiveness |
| **Measurement** | `(successful_connections / total_connection_attempts) × 100` |
| **Good Event** | Connection established and query executed |
| **Bad Event** | Connection timeout or failure |
| **Data Source** | Application metrics / synthetic monitoring |
| **Window** | Rolling 30 days |

#### 7. ATP Database Latency

| Property | Value |
|----------|-------|
| **Description** | Query response time |
| **Measurement** | Query latency percentiles |
| **Good Event** | Query completes within threshold |
| **Data Source** | Application metrics / OCI Database metrics |
| **Window** | Rolling 30 days |

### Secrets Management

#### 8. External Secrets Sync Success

| Property | Value |
|----------|-------|
| **Description** | Percentage of successful secret synchronizations |
| **Measurement** | `(successful_syncs / total_sync_attempts) × 100` |
| **Good Event** | ExternalSecret status is SecretSynced |
| **Bad Event** | ExternalSecret status is Error |
| **Data Source** | external_secrets_sync_calls_total metric |
| **Window** | Rolling 30 days |

```promql
# ESO sync success rate
sum(rate(externalsecret_status_condition{condition="SecretSynced", status="True"}[5m])) 
/ 
sum(rate(externalsecret_status_condition{condition="SecretSynced"}[5m])) * 100
```

---

## Service Level Objectives (SLOs)

### Production Tier SLOs

| Service | SLI | SLO Target | Measurement Window |
|---------|-----|------------|-------------------|
| **Kubernetes API** | Availability | 99.95% | 30 days rolling |
| **Kubernetes API** | Latency (p95) | < 500ms | 30 days rolling |
| **Kubernetes API** | Latency (p99) | < 1s | 30 days rolling |
| **Worker Nodes** | Availability | 99.9% | 30 days rolling |
| **Ingress** | Availability | 99.9% | 30 days rolling |
| **Ingress** | Latency (p95) | < 200ms | 30 days rolling |
| **Ingress** | Latency (p99) | < 500ms | 30 days rolling |
| **ATP Database** | Availability | 99.95% | 30 days rolling |
| **ATP Database** | Latency (p95) | < 100ms | 30 days rolling |
| **Secrets Sync** | Success Rate | 99.9% | 30 days rolling |
| **Secrets Sync** | Freshness | < 2 hours | Continuous |

### SLO Definitions

#### Kubernetes API: 99.95% Availability

- **Allowed Downtime (30 days)**: 21.6 minutes
- **Allowed Downtime (per month)**: ~22 minutes
- **Allowed Downtime (per year)**: ~4.4 hours

#### ATP Database: 99.95% Availability

- **Allowed Downtime (30 days)**: 21.6 minutes
- **Backed by**: OCI ATP SLA (99.95% with Data Guard)
- **Excludes**: Planned maintenance windows (with 7-day notice)

#### Ingress: 99.9% Availability

- **Allowed Downtime (30 days)**: 43.2 minutes
- **Allowed Error Rate**: 0.1% of requests may fail
- **Excludes**: Client-side errors (4xx)

---

## Service Level Agreement (SLA)

### Composite Platform SLA

Based on the underlying OCI SLAs and our SLO targets, the platform provides the following SLA:

| Metric | Commitment | Measurement |
|--------|------------|-------------|
| **Platform Availability** | 99.9% | Monthly |
| **Data Durability** | 99.999999999% (11 9s) | Annual |
| **Recovery Time Objective** | ≤ 1 hour | Per incident |
| **Recovery Point Objective** | ≤ 5 minutes | Per incident |

### SLA Calculation

```
Platform Availability = min(K8s API, Nodes, Ingress, Database)
                     = min(99.95%, 99.9%, 99.9%, 99.95%)
                     = 99.9%
```

### Monthly Uptime Commitment

| Uptime Percentage | Monthly Downtime | Service Credit |
|-------------------|------------------|----------------|
| ≥ 99.9% | ≤ 43.8 minutes | None |
| 99.0% - 99.9% | 43.8 min - 7.3 hours | 10% |
| 95.0% - 99.0% | 7.3 - 36.5 hours | 25% |
| < 95.0% | > 36.5 hours | 50% |

### SLA Exclusions

The SLA does not apply during:

1. **Planned Maintenance**: Scheduled with 7+ days notice
2. **Force Majeure**: Natural disasters, war, government actions
3. **Customer Actions**: Misconfigurations, unauthorized access
4. **Third-Party Failures**: External dependencies outside OCI
5. **Beta/Preview Features**: Non-GA OCI services

### Underlying OCI SLAs

| OCI Service | OCI SLA | Documentation |
|-------------|---------|---------------|
| OKE Control Plane | 99.95% | [OCI Compute SLA](https://www.oracle.com/cloud/sla/) |
| ATP with Data Guard | 99.95% | [OCI Database SLA](https://www.oracle.com/cloud/sla/) |
| Network Load Balancer | 99.99% | [OCI Networking SLA](https://www.oracle.com/cloud/sla/) |
| OCI Vault | 99.9% | [OCI Security SLA](https://www.oracle.com/cloud/sla/) |
| Object Storage | 99.9% | [OCI Storage SLA](https://www.oracle.com/cloud/sla/) |

---

## Error Budgets

### Error Budget Calculation

```
Error Budget = 100% - SLO Target

Example (99.9% SLO over 30 days):
- Total minutes: 43,200 (30 days × 24 hours × 60 min)
- Error budget: 0.1% × 43,200 = 43.2 minutes of allowed downtime
```

### Error Budget Policy

#### Budget Consumption Thresholds

| Consumed | Status | Action |
|----------|--------|--------|
| 0-50% | 🟢 Healthy | Normal operations, feature development continues |
| 50-75% | 🟡 Warning | Increased monitoring, prioritize stability work |
| 75-90% | 🟠 Critical | Feature freeze, focus on reliability improvements |
| 90-100% | 🔴 Exhausted | Incident mode, all hands on reliability |
| >100% | ⚫ Breached | Post-mortem required, SLA credit triggered |

#### Burn Rate Alerts

Configure alerts based on error budget burn rate:

```yaml
# Prometheus alerting rules
groups:
  - name: slo-alerts
    rules:
      # Fast burn: 14.4x burn rate over 1 hour = 2% budget consumed
      - alert: SLOErrorBudgetFastBurn
        expr: |
          (
            1 - (sum(rate(apiserver_request_total{code!~"5.."}[1h])) 
                 / sum(rate(apiserver_request_total[1h])))
          ) > (14.4 * 0.001)  # 14.4x of 0.1% error rate
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "High error budget burn rate detected"
          
      # Slow burn: 3x burn rate over 6 hours
      - alert: SLOErrorBudgetSlowBurn
        expr: |
          (
            1 - (sum(rate(apiserver_request_total{code!~"5.."}[6h])) 
                 / sum(rate(apiserver_request_total[6h])))
          ) > (3 * 0.001)
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: "Elevated error budget consumption detected"
```

### Error Budget Reset

- **Reset Period**: First day of each calendar month
- **Carry-over**: Error budget does not carry over
- **Reporting**: Monthly error budget report generated on 1st

---

## Monitoring Prerequisites

### Required Monitoring Stack

SLO tracking requires the following monitoring infrastructure, deployed via ArgoCD from the application repository:

| Component | Purpose | Required |
|-----------|---------|----------|
| **Prometheus** | Metrics collection and storage | ✅ Required |
| **Grafana** | SLO dashboards and visualization | ✅ Required |
| **Alertmanager** | SLO breach alerting | ✅ Required |
| **Prometheus Adapter** | Custom metrics for HPA | Recommended |
| **Loki** | Log aggregation for debugging | Recommended |

### Required Metrics Exporters

| Exporter | Metrics Provided |
|----------|------------------|
| kube-state-metrics | Node, pod, deployment status |
| metrics-server | CPU/memory utilization |
| NGINX Ingress Exporter | Request latency, error rates |
| External Secrets Exporter | Sync status, errors |

### Grafana SLO Dashboard

The following dashboard panels are required for SLO tracking:

1. **SLO Overview**: Current SLO compliance percentage
2. **Error Budget Remaining**: Percentage of budget remaining
3. **Burn Rate**: Current burn rate vs sustainable rate
4. **SLI Trends**: Historical SLI values over time
5. **Incident Timeline**: Correlation with deployments/changes

### ArgoCD Application Reference

```yaml
# Example: Monitoring stack ArgoCD Application
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: monitoring
  namespace: argocd
spec:
  project: platform
  source:
    repoURL: https://github.com/org/argocd-apps.git
    path: monitoring
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

---

## Escalation and Breach Response

### SLO Breach Response

#### Immediate Actions (within 15 minutes)

1. **Acknowledge**: On-call engineer acknowledges alert
2. **Assess**: Determine scope and impact
3. **Communicate**: Update status page if customer-facing
4. **Mitigate**: Implement immediate fixes or rollback

#### Post-Incident (within 48 hours)

1. **Incident Report**: Document timeline and impact
2. **Root Cause Analysis**: Identify contributing factors
3. **Action Items**: Define preventive measures
4. **Error Budget Review**: Update budget consumption tracking

### SLA Breach Response

#### If SLA is breached:

1. **Notify Stakeholders**: Inform leadership and affected customers
2. **Calculate Credits**: Determine service credits owed
3. **Conduct Post-Mortem**: Formal blameless post-mortem
4. **Improvement Plan**: Document and implement improvements
5. **Customer Communication**: Formal apology and remediation plan

### Escalation Matrix

| Condition | Escalation Level | Notify |
|-----------|------------------|--------|
| Error budget < 50% | L1 - On-call | Team Slack channel |
| Error budget < 25% | L2 - Team Lead | Team lead + management |
| SLO breached | L3 - Management | Director + stakeholders |
| SLA breached | L4 - Executive | VP/CTO + customer success |

---

## Reporting

### Weekly SLO Report

Generated every Monday, includes:

- Current SLO compliance for each service
- Error budget remaining
- Week-over-week trend
- Notable incidents

### Monthly SLA Report

Generated on 1st of each month, includes:

- Monthly availability achieved
- SLA compliance status
- Service credits (if applicable)
- Error budget reset status
- Top contributing incidents

### Quarterly Review

- SLO target adjustment recommendations
- Infrastructure improvements needed
- Capacity planning updates
- SLA term review

---

*Last Updated: February 2026*
*Document Owner: Platform Engineering Team*
*Review Cycle: Quarterly*
