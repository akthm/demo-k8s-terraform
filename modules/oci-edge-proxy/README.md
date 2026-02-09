# OCI Edge Proxy Module

Creates an Always Free VM running NGINX as a reverse proxy for Kubernetes ingress.

## Features

- Always Free eligible (VM.Standard.E2.1.Micro)
- NGINX reverse proxy to K8s NodePorts
- Let's Encrypt certificate support (certbot)
- Cloud-init automated setup
- Public IP for ingress traffic
- Configurable backend IPs and ports

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                                                              │
│  Internet                                                    │
│      │                                                       │
│      ▼ (80/443)                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Edge Proxy VM (VM.Standard.E2.1.Micro)              │   │
│  │  Public Subnet: 10.0.10.0/24                          │   │
│  │                                                        │   │
│  │  ┌────────────────────────────────────────────────┐  │   │
│  │  │  NGINX                                          │  │   │
│  │  │  - Listen 80  → Proxy to NodePort 30080        │  │   │
│  │  │  - Listen 443 → Proxy to NodePort 30443        │  │   │
│  │  │  - Let's Encrypt TLS                           │  │   │
│  │  └────────────────────────────────────────────────┘  │   │
│  └─────────────────────┬────────────────────────────────┘   │
│                        │                                     │
│                        ▼                                     │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Private Subnet: 10.0.20.0/24                         │   │
│  │                                                        │   │
│  │  ┌────────────┐  ┌────────────┐                      │   │
│  │  │ Worker 1   │  │ Worker 2   │                      │   │
│  │  │ NodePort   │  │ NodePort   │                      │   │
│  │  │ 30080/30443│  │ 30080/30443│                      │   │
│  │  └────────────┘  └────────────┘                      │   │
│  │         ▲               ▲                             │   │
│  │         └───────┬───────┘                             │   │
│  │                 │                                     │   │
│  │  ┌──────────────▼──────────────┐                     │   │
│  │  │  NGINX Ingress Controller   │                     │   │
│  │  │  (K8s Service: NodePort)    │                     │   │
│  │  └─────────────────────────────┘                     │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Usage

```hcl
module "edge_proxy" {
  source = "../../modules/oci-edge-proxy"

  compartment_id = var.compartment_id
  tenancy_ocid   = var.tenancy_ocid
  
  # VM configuration
  edge_name  = "oke-edge-proxy"
  edge_shape = "VM.Standard.E2.1.Micro"
  
  # Network
  subnet_id = module.network.public_subnet_id
  
  # Backend K8s workers
  backend_ips = [
    "10.0.20.10",
    "10.0.20.11",
  ]
  ingress_http_nodeport  = 30080
  ingress_https_nodeport = 30443
  
  # SSH access
  ssh_public_key = file("~/.ssh/id_rsa.pub")

  common_tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `compartment_id` | OCI Compartment OCID | `string` | - | Yes |
| `tenancy_ocid` | OCI Tenancy OCID | `string` | - | Yes |
| `edge_name` | VM instance name | `string` | - | Yes |
| `edge_shape` | Compute shape | `string` | `"VM.Standard.E2.1.Micro"` | No |
| `subnet_id` | Public subnet OCID | `string` | - | Yes |
| `backend_ips` | Worker node private IPs | `list(string)` | - | Yes |
| `ingress_http_nodeport` | NGINX ingress HTTP NodePort | `number` | `30080` | No |
| `ingress_https_nodeport` | NGINX ingress HTTPS NodePort | `number` | `30443` | No |
| `ssh_public_key` | SSH public key content | `string` | - | Yes |
| `os_version` | Oracle Linux version | `string` | `"8"` | No |
| `common_tags` | Tags to apply | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| `instance_id` | Instance OCID |
| `public_ip` | Public IP address |
| `private_ip` | Private IP address |

## NGINX Configuration

The module creates an NGINX configuration that:

1. **HTTP (port 80)**: Proxies to K8s ingress HTTP NodePort
2. **HTTPS (port 443)**: Proxies to K8s ingress HTTPS NodePort
3. **Health checks**: Configures upstream health checks
4. **Headers**: Forwards client IP and protocol headers

### Generated NGINX Config

```nginx
upstream k8s_ingress_http {
    server 10.0.20.10:30080;
    server 10.0.20.11:30080;
}

upstream k8s_ingress_https {
    server 10.0.20.10:30443;
    server 10.0.20.11:30443;
}

server {
    listen 80;
    location / {
        proxy_pass http://k8s_ingress_http;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

server {
    listen 443 ssl;
    # SSL configuration...
    location / {
        proxy_pass https://k8s_ingress_https;
        # Headers...
    }
}
```

## TLS Certificates

### Let's Encrypt (Recommended)

SSH to the edge proxy and run certbot:

```bash
# SSH to edge proxy
ssh opc@<public-ip>

# Obtain certificate
sudo certbot --nginx -d yourdomain.com

# Auto-renewal is configured automatically
```

### Custom Certificate

```bash
# Copy certificates
scp cert.pem key.pem opc@<public-ip>:/tmp/

# SSH and configure
ssh opc@<public-ip>
sudo mv /tmp/cert.pem /etc/nginx/ssl/
sudo mv /tmp/key.pem /etc/nginx/ssl/
sudo nginx -s reload
```

## Updating Backend IPs

When worker nodes change (scale up/down), update the backend IPs:

```bash
# Update in Terraform
cd live/oci-staging/edge-proxy
terragrunt apply -var='backend_ips=["10.0.20.10","10.0.20.11","10.0.20.12"]'
```

Or manually on the VM:

```bash
ssh opc@<public-ip>
sudo vi /etc/nginx/conf.d/kubernetes-ingress.conf
sudo nginx -t
sudo systemctl reload nginx
```

## NGINX Ingress Controller Setup

Configure the NGINX Ingress Controller to use NodePort:

```yaml
# values.yaml for NGINX Ingress Helm chart
controller:
  service:
    type: NodePort
    nodePorts:
      http: 30080
      https: 30443
```

## Cost

| Resource | Always Free | Paid |
|----------|-------------|------|
| VM.Standard.E2.1.Micro | 2 instances | ~$5/month |
| Boot Volume (50GB) | Yes | - |
| Public IP | Yes | - |

## Troubleshooting

### NGINX Not Starting

```bash
ssh opc@<public-ip>

# Check NGINX status
sudo systemctl status nginx

# Test configuration
sudo nginx -t

# View logs
sudo tail -f /var/log/nginx/error.log
```

### Backend Connection Refused

```bash
# Test connectivity to workers
curl -v http://10.0.20.10:30080

# Check K8s service
kubectl get svc -n ingress-nginx

# Verify NodePort is listening
kubectl get pods -n ingress-nginx -o wide
```

### Cloud-Init Failed

```bash
ssh opc@<public-ip>

# Check cloud-init logs
sudo cat /var/log/cloud-init-output.log

# Re-run cloud-init
sudo cloud-init clean
sudo cloud-init init
```

## Alternatives

| Solution | Pros | Cons |
|----------|------|------|
| **Edge Proxy VM** | Free, full control | Manual management |
| **OCI Load Balancer** | Managed, HA | ~$20/month minimum |
| **OCI Network LB** | Lower cost, L4 | No L7 features |

## Notes

- E2.1.Micro has 1 OCPU, 1 GB RAM - sufficient for light traffic
- For high traffic, consider OCI Load Balancer instead
- Keep NGINX and OS updated for security patches
- Monitor CPU/memory to detect capacity issues
