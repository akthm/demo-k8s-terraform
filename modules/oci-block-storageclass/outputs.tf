################################################################################
# OCI Block Volume StorageClass Module - Outputs
################################################################################

output "storage_class_name" {
  description = "Name of the default storage class"
  value       = kubernetes_storage_class.oci_block.metadata[0].name
}

output "storage_class_provisioner" {
  description = "CSI provisioner for the storage class"
  value       = kubernetes_storage_class.oci_block.storage_provisioner
}

output "high_perf_storage_class_name" {
  description = "Name of the high-performance storage class (if created)"
  value       = var.create_high_perf_class ? kubernetes_storage_class.oci_block_high_perf[0].metadata[0].name : null
}

output "balanced_storage_class_name" {
  description = "Name of the balanced storage class (if created)"
  value       = var.create_balanced_class ? kubernetes_storage_class.oci_block_balanced[0].metadata[0].name : null
}

output "storage_classes_created" {
  description = "List of all storage classes created"
  value = compact([
    kubernetes_storage_class.oci_block.metadata[0].name,
    var.create_high_perf_class ? kubernetes_storage_class.oci_block_high_perf[0].metadata[0].name : null,
    var.create_balanced_class ? kubernetes_storage_class.oci_block_balanced[0].metadata[0].name : null,
  ])
}
