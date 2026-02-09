# OCI Network Load Balancer Module

Creates an OCI Network Load Balancer (Always Free tier - 10 Mbps flexible) for routing traffic to Kubernetes NodePorts.

## Features

- **Always Free Compatible**: Uses flexible shape with 10 Mbps bandwidth
- **High Availability**: Managed service with automatic failover
- **Health Checks**: TCP health checks on backend nodes
- **Dynamic Backends**: Accepts list of worker node IPs
- **Session Persistence**: 5-tuple hash for consistent routing

## Usage

```hcl
module "network_lb" {
  source = "../../modules/oci-network-lb"

  compartment_id    = var.compartment_id
  lb_name           = "oke-staging-lb"
  public_subnet_id  = var.public_subnet_id
  
  backend_ips       = ["10.0.20.166", "10.0.20.210"]
  http_nodeport     = 30080
  https_nodeport    = 30443
  
  common_tags       = var.common_tags
}
```

## Architecture

```
Internet → Network Load Balancer (port 80/443)
             ↓
          Backend Set (with health checks)
             ↓
    Worker Nodes (NodePort 30080/30443)
             ↓
    Kubernetes Ingress Controller
             ↓
          Services
```

## Outputs

- `load_balancer_ip` - Public IP for DNS configuration
- `load_balancer_state` - Current state (ACTIVE, CREATING, etc.)
- `backend_ips` - Configured backend IPs

## Always Free Tier Limits

- **1 flexible load balancer** per tenancy (10 Mbps)
- No bandwidth charges for Always Free tier
- Included health checks
