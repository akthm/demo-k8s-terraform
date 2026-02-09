################################################################################
# OCI Network Load Balancer Module
# Always Free: Flexible Load Balancer (10 Mbps)
# Forwards traffic to Kubernetes NodePorts on worker nodes
################################################################################

terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
  }
}

# Network Load Balancer
resource "oci_network_load_balancer_network_load_balancer" "main" {
  compartment_id = var.compartment_id
  display_name   = var.lb_name
  subnet_id      = var.public_subnet_id

  # Always Free: flexible shape with 10 Mbps bandwidth
  is_private                     = false
  is_preserve_source_destination = false

  freeform_tags = var.common_tags
}

# Backend Set for HTTP traffic (NodePort 30080)
resource "oci_network_load_balancer_backend_set" "http" {
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.main.id
  name                     = "http-backends"
  policy                   = "FIVE_TUPLE" # 5-tuple hash for session persistence

  health_checker {
    protocol           = "TCP"
    port               = var.http_nodeport
    interval_in_millis = 10000
    timeout_in_millis  = 3000
    retries            = 3
  }

  is_preserve_source = false
}

# Backend Set for HTTPS traffic (NodePort 30443)
resource "oci_network_load_balancer_backend_set" "https" {
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.main.id
  name                     = "https-backends"
  policy                   = "FIVE_TUPLE"

  health_checker {
    protocol           = "TCP"
    port               = var.https_nodeport
    interval_in_millis = 10000
    timeout_in_millis  = 3000
    retries            = 3
  }

  is_preserve_source = false
}

# HTTP Backends (worker nodes)
resource "oci_network_load_balancer_backend" "http" {
  count = length(var.backend_ips)

  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.main.id
  backend_set_name         = oci_network_load_balancer_backend_set.http.name
  
  name       = "http-backend-${count.index + 1}"
  ip_address = var.backend_ips[count.index]
  port       = var.http_nodeport
  is_backup  = false
  is_drain   = false
  is_offline = false
  weight     = 1
}

# HTTPS Backends (worker nodes)
resource "oci_network_load_balancer_backend" "https" {
  count = length(var.backend_ips)

  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.main.id
  backend_set_name         = oci_network_load_balancer_backend_set.https.name
  
  name       = "https-backend-${count.index + 1}"
  ip_address = var.backend_ips[count.index]
  port       = var.https_nodeport
  is_backup  = false
  is_drain   = false
  is_offline = false
  weight     = 1
}

# HTTP Listener (port 80)
resource "oci_network_load_balancer_listener" "http" {
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.main.id
  name                     = "http-listener"
  default_backend_set_name = oci_network_load_balancer_backend_set.http.name
  protocol                 = "TCP"
  port                     = 80
}

# HTTPS Listener (port 443)
resource "oci_network_load_balancer_listener" "https" {
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.main.id
  name                     = "https-listener"
  default_backend_set_name = oci_network_load_balancer_backend_set.https.name
  protocol                 = "TCP"
  port                     = 443
}
