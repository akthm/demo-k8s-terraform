################################################################################
# OCI Block Volume StorageClass Module
# Creates Kubernetes StorageClass for OCI Block Volume CSI driver
################################################################################

resource "kubernetes_storage_class" "oci_block" {
  metadata {
    name = var.storage_class_name

    annotations = {
      "storageclass.kubernetes.io/is-default-class" = var.is_default ? "true" : "false"
    }

    labels = var.labels
  }

  storage_provisioner = "blockvolume.csi.oraclecloud.com"

  parameters = {
    # Volume performance tier
    vpusPerGB = tostring(var.vpus_per_gb)
    
    # Attachment type
    attachmentType = var.attachment_type
  }

  reclaim_policy         = var.reclaim_policy
  volume_binding_mode    = var.volume_binding_mode
  allow_volume_expansion = var.allow_expansion
}

# Optional: Create a high-performance storage class
resource "kubernetes_storage_class" "oci_block_high_perf" {
  count = var.create_high_perf_class ? 1 : 0

  metadata {
    name = "${var.storage_class_name}-high-perf"

    labels = var.labels
  }

  storage_provisioner = "blockvolume.csi.oraclecloud.com"

  parameters = {
    # Higher performance (20 VPUs = Higher Performance)
    vpusPerGB      = "20"
    attachmentType = "paravirtualized"
  }

  reclaim_policy         = var.reclaim_policy
  volume_binding_mode    = var.volume_binding_mode
  allow_volume_expansion = var.allow_expansion
}

# Optional: Create a balanced storage class
resource "kubernetes_storage_class" "oci_block_balanced" {
  count = var.create_balanced_class ? 1 : 0

  metadata {
    name = "${var.storage_class_name}-balanced"

    labels = var.labels
  }

  storage_provisioner = "blockvolume.csi.oraclecloud.com"

  parameters = {
    # Balanced performance (10 VPUs)
    vpusPerGB      = "10"
    attachmentType = "paravirtualized"
  }

  reclaim_policy         = var.reclaim_policy
  volume_binding_mode    = var.volume_binding_mode
  allow_volume_expansion = var.allow_expansion
}
