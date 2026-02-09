################################################################################
# OKE Node Pool Module - Outputs
################################################################################

output "node_pool_id" {
  description = "The OCID of the node pool"
  value       = oci_containerengine_node_pool.main.id
}

output "node_pool_name" {
  description = "The name of the node pool"
  value       = oci_containerengine_node_pool.main.name
}

output "node_pool_kubernetes_version" {
  description = "The Kubernetes version of the node pool"
  value       = oci_containerengine_node_pool.main.kubernetes_version
}

output "node_pool_state" {
  description = "The current state of the node pool"
  value       = oci_containerengine_node_pool.main.state
}

output "node_count" {
  description = "The number of nodes in the pool"
  value       = var.worker_count
}

output "node_shape" {
  description = "The compute shape of the nodes"
  value       = var.worker_shape
}

output "node_ocpus" {
  description = "OCPUs per node"
  value       = var.worker_ocpus
}

output "node_memory_gb" {
  description = "Memory in GB per node"
  value       = var.worker_memory_gb
}

output "total_ocpus" {
  description = "Total OCPUs across all nodes"
  value       = var.worker_count * var.worker_ocpus
}

output "total_memory_gb" {
  description = "Total memory in GB across all nodes"
  value       = var.worker_count * var.worker_memory_gb
}

output "total_boot_volume_gb" {
  description = "Total boot volume in GB across all nodes"
  value       = var.worker_count * var.worker_boot_volume_gb
}

output "always_free_capacity_used" {
  description = "Summary of Always Free capacity usage"
  value = {
    ocpus_used             = "${var.worker_count * var.worker_ocpus}/4"
    memory_used            = "${var.worker_count * var.worker_memory_gb}/24 GB"
    boot_volume_used       = "${var.worker_count * var.worker_boot_volume_gb}/200 GB"
  }
}

output "node_image_id" {
  description = "The image ID being used for the nodes"
  value       = oci_containerengine_node_pool.main.node_source_details[0].image_id
}

output "node_image_info" {
  description = "Node image selection info"
  value = {
    shape_architecture = local.is_arm_shape ? "ARM" : "x86"
    selected_image_id  = var.node_image_id != "" ? var.node_image_id : local.default_image_id
    available_images_count = length(local.oke_images_for_arch)
  }
}

output "node_private_ips" {
  description = "Private IP addresses of worker nodes"
  value       = [for vnic in data.oci_core_vnic.node_vnic : vnic.private_ip_address]
}

output "node_ids" {
  description = "OCIDs of worker node instances"
  value       = [for node in data.oci_containerengine_node_pool.nodes.nodes : node.id]
}
