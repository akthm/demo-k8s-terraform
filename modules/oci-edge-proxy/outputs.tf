################################################################################
# OCI Edge Proxy Module - Outputs
################################################################################

output "edge_proxy_id" {
  description = "The OCID of the edge proxy instance"
  value       = var.enable_edge_proxy ? oci_core_instance.edge_proxy[0].id : null
}

output "edge_proxy_private_ip" {
  description = "The private IP of the edge proxy"
  value       = var.enable_edge_proxy ? oci_core_instance.edge_proxy[0].private_ip : null
}

output "edge_proxy_public_ip" {
  description = "The public IP of the edge proxy"
  value       = var.enable_edge_proxy ? oci_core_instance.edge_proxy[0].public_ip : null
}

output "edge_proxy_reserved_ip" {
  description = "The reserved public IP (if enabled)"
  value       = var.enable_edge_proxy && var.use_reserved_ip ? oci_core_public_ip.edge_proxy[0].ip_address : null
}

output "edge_proxy_state" {
  description = "The current state of the edge proxy instance"
  value       = var.enable_edge_proxy ? oci_core_instance.edge_proxy[0].state : null
}

output "dns_record_value" {
  description = "The IP address to use for DNS A record (reserved if available, else ephemeral)"
  value       = var.enable_edge_proxy ? (var.use_reserved_ip ? oci_core_public_ip.edge_proxy[0].ip_address : oci_core_instance.edge_proxy[0].public_ip) : null
}

output "nginx_config_note" {
  description = "Note about NGINX configuration"
  value       = <<-EOT
    Edge proxy is configured with:
    - HTTP on port 80 → NodePort ${var.ingress_http_nodeport}
    - HTTPS on port 443 → NodePort ${var.ingress_https_nodeport}
    
    To configure Let's Encrypt:
    1. SSH to edge proxy: ssh opc@<public_ip>
    2. Run: sudo certbot --nginx -d yourdomain.com
    
    To update backend IPs after node pool creation:
    1. Get node private IPs from OCI console or terraform output
    2. Update the backend_ips variable
    3. Re-apply this module
  EOT
}
