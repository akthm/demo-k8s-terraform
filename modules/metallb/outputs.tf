output "ip_pool_range" {
  description = "The IP address range allocated to MetalLB"
  value       = var.ip_address_pool.addresses
}

output "ip_pool_name" {
  description = "The name of the IP address pool"
  value       = var.ip_address_pool.name
}

output "namespace" {
  description = "The namespace where MetalLB is installed"
  value       = helm_release.metallb.namespace
}
