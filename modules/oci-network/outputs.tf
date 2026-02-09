################################################################################
# OCI Network Module - Outputs
################################################################################

output "vcn_id" {
  description = "The OCID of the VCN"
  value       = oci_core_vcn.main.id
}

output "vcn_cidr" {
  description = "The CIDR block of the VCN"
  value       = oci_core_vcn.main.cidr_blocks[0]
}

output "public_subnet_id" {
  description = "The OCID of the public subnet"
  value       = oci_core_subnet.public.id
}

output "public_subnet_cidr" {
  description = "The CIDR block of the public subnet"
  value       = oci_core_subnet.public.cidr_block
}

output "private_subnet_id" {
  description = "The OCID of the private subnet"
  value       = oci_core_subnet.private.id
}

output "private_subnet_cidr" {
  description = "The CIDR block of the private subnet"
  value       = oci_core_subnet.private.cidr_block
}

output "internet_gateway_id" {
  description = "The OCID of the Internet Gateway"
  value       = oci_core_internet_gateway.main.id
}

output "nat_gateway_id" {
  description = "The OCID of the NAT Gateway (if enabled)"
  value       = var.enable_nat_gateway ? oci_core_nat_gateway.main[0].id : null
}

output "nat_gateway_public_ip" {
  description = "The public IP address of the NAT Gateway (needed for ATP whitelist)"
  value       = var.enable_nat_gateway ? oci_core_nat_gateway.main[0].nat_ip : null
}

output "service_gateway_id" {
  description = "The OCID of the Service Gateway (if enabled)"
  value       = var.enable_service_gateway ? oci_core_service_gateway.main[0].id : null
}

output "public_route_table_id" {
  description = "The OCID of the public route table"
  value       = oci_core_route_table.public.id
}

output "private_route_table_id" {
  description = "The OCID of the private route table"
  value       = oci_core_route_table.private.id
}

output "public_security_list_id" {
  description = "The OCID of the public security list"
  value       = oci_core_security_list.public.id
}

output "private_security_list_id" {
  description = "The OCID of the private security list"
  value       = oci_core_security_list.private.id
}

output "availability_domains" {
  description = "List of availability domains in the region"
  value       = data.oci_identity_availability_domains.ads.availability_domains[*].name
}
