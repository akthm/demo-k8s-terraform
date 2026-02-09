################################################################################
# OCI Edge Proxy Module - Always Free Reverse Proxy VM
# VM.Standard.E2.1.Micro (Always Free eligible - up to 2 instances)
# Acts as public ingress point, forwarding to K8s NodePorts on private workers
################################################################################

# Get availability domain
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# Get latest Oracle Linux image for E2.1.Micro
data "oci_core_images" "oracle_linux" {
  compartment_id           = var.compartment_id
  operating_system         = "Oracle Linux"
  operating_system_version = var.os_version
  shape                    = var.edge_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# Cloud-init script for NGINX reverse proxy setup
locals {
  cloud_init_script = <<-EOF
    #!/bin/bash
    set -e

    # Update system
    dnf update -y

    # Install NGINX
    dnf install -y nginx

    # Install certbot for Let's Encrypt
    dnf install -y epel-release || true
    dnf install -y certbot python3-certbot-nginx || true

    # Create NGINX config for reverse proxy
    cat > /etc/nginx/conf.d/kubernetes-ingress.conf <<'NGINX'
    # Upstream to Kubernetes Ingress Controller NodePort
    upstream k8s_ingress_http {
        ${join("\n        ", [for ip in var.backend_ips : "server ${ip}:${var.ingress_http_nodeport};"])}
    }

    upstream k8s_ingress_https {
        ${join("\n        ", [for ip in var.backend_ips : "server ${ip}:${var.ingress_https_nodeport};"])}
    }

    # HTTP server - redirect to HTTPS or proxy
    server {
        listen 80;
        server_name _;

        location / {
            proxy_pass http://k8s_ingress_http;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_connect_timeout 60s;
            proxy_read_timeout 60s;
        }
    }

    # HTTPS server (SSL termination at edge, or passthrough)
    server {
        listen 443 ssl;
        server_name _;

        # Placeholder certs - replace with Let's Encrypt
        ssl_certificate /etc/nginx/ssl/server.crt;
        ssl_certificate_key /etc/nginx/ssl/server.key;

        location / {
            proxy_pass http://k8s_ingress_http;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_connect_timeout 60s;
            proxy_read_timeout 60s;
        }
    }
    NGINX

    # Create self-signed placeholder certs
    mkdir -p /etc/nginx/ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/server.key \
        -out /etc/nginx/ssl/server.crt \
        -subj "/CN=edge-proxy"

    # Enable and start NGINX
    systemctl enable nginx
    systemctl start nginx

    # Open firewall
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --reload

    echo "Edge proxy setup complete!"
  EOF
}

# Edge Proxy VM
resource "oci_core_instance" "edge_proxy" {
  count = var.enable_edge_proxy ? 1 : 0

  compartment_id      = var.compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = var.edge_name
  shape               = var.edge_shape

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.oracle_linux.images[0].id
    boot_volume_size_in_gbs = var.edge_boot_volume_gb
  }

  create_vnic_details {
    subnet_id                 = var.public_subnet_id
    assign_public_ip          = var.assign_public_ip
    display_name              = "${var.edge_name}-vnic"
    skip_source_dest_check    = false
    assign_private_dns_record = true
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(local.cloud_init_script)
  }

  freeform_tags = var.common_tags

  lifecycle {
    precondition {
      condition     = var.edge_boot_volume_gb <= 50
      error_message = "Edge proxy boot volume should be ≤50 GB to leave room for OKE nodes under 200 GB total."
    }
  }
}

# Get the VNIC attachment to find the private IP
data "oci_core_vnic_attachments" "edge_proxy" {
  count = var.enable_edge_proxy ? 1 : 0

  compartment_id = var.compartment_id
  instance_id    = oci_core_instance.edge_proxy[0].id
}

data "oci_core_vnic" "edge_proxy" {
  count = var.enable_edge_proxy ? 1 : 0

  vnic_id = data.oci_core_vnic_attachments.edge_proxy[0].vnic_attachments[0].vnic_id
}

data "oci_core_private_ips" "edge_proxy" {
  count = var.enable_edge_proxy ? 1 : 0

  vnic_id = data.oci_core_vnic.edge_proxy[0].id
}

# Reserved public IP (optional - for stable DNS)
resource "oci_core_public_ip" "edge_proxy" {
  count = var.enable_edge_proxy && var.use_reserved_ip ? 1 : 0

  compartment_id = var.compartment_id
  display_name   = "${var.edge_name}-public-ip"
  lifetime       = "RESERVED"
  private_ip_id  = data.oci_core_private_ips.edge_proxy[0].private_ips[0].id

  freeform_tags = var.common_tags
}
