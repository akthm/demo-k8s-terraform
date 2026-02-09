################################################################################
# OKE Node Pool Module - Worker Nodes for OKE
# Configured for Always Free: 2x VM.Standard.A1.Flex (2 OCPU / 12GB each)
################################################################################

# Get available Kubernetes versions
data "oci_containerengine_node_pool_option" "main" {
  node_pool_option_id = "all"
  compartment_id      = var.compartment_id
}

# Get the latest OKE-optimized image for the node shape
data "oci_containerengine_node_pool_option" "images" {
  node_pool_option_id = "all"
  compartment_id      = var.compartment_id
}

locals {
  # Determine architecture based on shape
  is_arm_shape = can(regex("(?i)A1\\.Flex", var.worker_shape))
  is_gpu_shape = can(regex("(?i)GPU", var.worker_shape))
  
  # Get OKE images matching the shape architecture and exclude GPU images for non-GPU shapes
  oke_images_for_arch = [
    for s in data.oci_containerengine_node_pool_option.images.sources : s.image_id
    if (
      s.source_type == "IMAGE" &&
      can(regex("(?i)oke", s.source_name)) &&
      # Filter out GPU images for non-GPU shapes
      (!local.is_gpu_shape ? !can(regex("(?i)gpu", s.source_name)) : true) &&
      (
        # For ARM shapes, need ARM images
        (local.is_arm_shape && can(regex("(?i)aarch64|arm", s.source_name))) ||
        # For x86 shapes (E4.Flex, E2.Micro, etc), need x86 images
        (!local.is_arm_shape && !can(regex("(?i)aarch64|arm", s.source_name)))
      )
    )
  ]

  default_image_id = (
    length(local.oke_images_for_arch) > 0 ? local.oke_images_for_arch[0] : ""
  )
}


# Node Pool
resource "oci_containerengine_node_pool" "main" {
  compartment_id = var.compartment_id
  cluster_id     = var.cluster_id
  name           = "${var.node_pool_name}-nodepool"

  kubernetes_version = var.kubernetes_version
  node_shape         = var.worker_shape

  # Flex shape configuration (OCPU and memory)
  node_shape_config {
    ocpus         = var.worker_ocpus
    memory_in_gbs = var.worker_memory_gb
  }

  # Node source (OKE-optimized image)
  node_source_details {
    source_type             = "IMAGE"
    image_id                = var.node_image_id != "" ? var.node_image_id : local.default_image_id
    boot_volume_size_in_gbs = var.worker_boot_volume_gb
  }

  # Node placement - single AD for Jerusalem
  node_config_details {
    size = var.worker_count

    # Single placement config for Jerusalem (1 AD)
    placement_configs {
      availability_domain = var.availability_domain
      subnet_id           = var.node_subnet_id
    }

    # PV encryption settings
    is_pv_encryption_in_transit_enabled = var.enable_pv_encryption

    # Node pool cycling settings (for upgrades)
    node_pool_pod_network_option_details {
      cni_type = var.cni_type
    }
  }

  # SSH key for node access (via Bastion)
  ssh_public_key = var.ssh_public_key

  # Initial node labels
  dynamic "initial_node_labels" {
    for_each = var.node_labels
    content {
      key   = initial_node_labels.key
      value = initial_node_labels.value
    }
  }

  freeform_tags = var.common_tags

  lifecycle {
    # Prevent accidental scale-up beyond Always Free limits
    precondition {
      condition     = local.default_image_id != "" || var.node_image_id != ""
      error_message = "No compatible OKE image found for shape ${var.worker_shape}. Architecture: ${local.is_arm_shape ? "ARM" : "x86"}. Found ${length(local.oke_images_for_arch)} matching images. Please specify node_image_id explicitly."
    }

    precondition {
      condition     = var.worker_count * var.worker_ocpus <= 4
      error_message = "Total OCPUs (${var.worker_count} workers × ${var.worker_ocpus} OCPUs) exceeds Always Free limit of 4 OCPUs."
    }

    precondition {
      condition     = var.worker_count * var.worker_memory_gb <= 24
      error_message = "Total memory (${var.worker_count} workers × ${var.worker_memory_gb} GB) exceeds Always Free limit of 24 GB."
    }

    precondition {
      condition     = var.worker_count * var.worker_boot_volume_gb <= 200
      error_message = "Total boot volume (${var.worker_count} workers × ${var.worker_boot_volume_gb} GB) exceeds Always Free limit of 200 GB."
    }
  }
}

# Get node pool instances to retrieve private IPs
data "oci_containerengine_node_pool" "nodes" {
  node_pool_id = oci_containerengine_node_pool.main.id
  
  depends_on = [oci_containerengine_node_pool.main]
}

# Get compute instances in the node pool to fetch private IPs
data "oci_core_instance" "nodes" {
  count = length(data.oci_containerengine_node_pool.nodes.nodes)
  
  instance_id = data.oci_containerengine_node_pool.nodes.nodes[count.index].id
}

# Get VNICs for each node to extract private IPs
data "oci_core_vnic_attachments" "node_vnics" {
  count = length(data.oci_containerengine_node_pool.nodes.nodes)
  
  compartment_id = var.compartment_id
  instance_id    = data.oci_containerengine_node_pool.nodes.nodes[count.index].id
}

data "oci_core_vnic" "node_vnic" {
  count = length(data.oci_containerengine_node_pool.nodes.nodes)
  
  vnic_id = data.oci_core_vnic_attachments.node_vnics[count.index].vnic_attachments[0].vnic_id
}
