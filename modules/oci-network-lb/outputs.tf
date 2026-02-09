################################################################################
# OCI Network Load Balancer Module - Outputs
################################################################################

output "load_balancer_id" {
  description = "OCID of the network load balancer"
  value       = oci_network_load_balancer_network_load_balancer.main.id
}

output "load_balancer_ip" {
  description = "Public IP address of the load balancer"
  value       = oci_network_load_balancer_network_load_balancer.main.ip_addresses[0].ip_address
}

output "load_balancer_state" {
  description = "Current state of the load balancer"
  value       = oci_network_load_balancer_network_load_balancer.main.state
}

output "http_backend_set_name" {
  description = "Name of the HTTP backend set"
  value       = oci_network_load_balancer_backend_set.http.name
}

output "https_backend_set_name" {
  description = "Name of the HTTPS backend set"
  value       = oci_network_load_balancer_backend_set.https.name
}

output "backend_ips" {
  description = "List of backend IPs configured"
  value       = var.backend_ips
}

output "dns_note" {
  description = "DNS configuration note"
  value       = <<-EOT
    Network Load Balancer deployed with IP: ${oci_network_load_balancer_network_load_balancer.main.ip_addresses[0].ip_address}
    
    Update your DNS A records to point to this IP:
    - keycloak.adaas-il.com → ${oci_network_load_balancer_network_load_balancer.main.ip_addresses[0].ip_address}
    
    Backends configured:
    ${join("\n    ", [for ip in var.backend_ips : "- ${ip}:${var.http_nodeport} (HTTP), ${ip}:${var.https_nodeport} (HTTPS)"])}
    
    Health checks: TCP probe every 10s
  EOT
}
