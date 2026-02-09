################################################################################
# OCI Network Module - Always Free Safe
# Creates VCN, subnets, gateways, and security rules for OKE
################################################################################

# VCN
resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_id
  display_name   = "${var.cluster_name}-vcn"
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = replace(var.cluster_name, "-", "")

  freeform_tags = var.common_tags
}

# Internet Gateway (Always Free)
resource "oci_core_internet_gateway" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.cluster_name}-igw"
  enabled        = true

  freeform_tags = var.common_tags
}

# NAT Gateway (PAID - disabled by default for Always Free)
resource "oci_core_nat_gateway" "main" {
  count = var.enable_nat_gateway ? 1 : 0

  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.cluster_name}-nat"

  freeform_tags = var.common_tags
}

# Service Gateway (optional - for OCI services private access)
data "oci_core_services" "all_oci_services" {
  count = var.enable_service_gateway ? 1 : 0

  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_service_gateway" "main" {
  count = var.enable_service_gateway ? 1 : 0

  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.cluster_name}-sgw"

  services {
    service_id = data.oci_core_services.all_oci_services[0].services[0].id
  }

  freeform_tags = var.common_tags
}

################################################################################
# Route Tables
################################################################################

# Public Route Table - routes to Internet Gateway
resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.cluster_name}-public-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main.id
  }

  freeform_tags = var.common_tags
}

# Private Route Table - routes to NAT Gateway if enabled, otherwise no external access
resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.cluster_name}-private-rt"

  dynamic "route_rules" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      destination       = "0.0.0.0/0"
      destination_type  = "CIDR_BLOCK"
      network_entity_id = oci_core_nat_gateway.main[0].id
    }
  }

  dynamic "route_rules" {
    for_each = var.enable_service_gateway ? [1] : []
    content {
      destination       = data.oci_core_services.all_oci_services[0].services[0].cidr_block
      destination_type  = "SERVICE_CIDR_BLOCK"
      network_entity_id = oci_core_service_gateway.main[0].id
    }
  }

  freeform_tags = var.common_tags
}

################################################################################
# Security Lists
################################################################################

# Public Subnet Security List (K8s API Endpoint Subnet)
resource "oci_core_security_list" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.cluster_name}-public-sl"

  # Egress - allow all outbound to internet
  egress_security_rules {
    destination      = "0.0.0.0/0"
    protocol         = "all"
    destination_type = "CIDR_BLOCK"
    stateless        = false
  }

  # Egress - K8s API to Oracle Services (OKE communication)
  dynamic "egress_security_rules" {
    for_each = var.enable_service_gateway ? [1] : []
    content {
      destination      = data.oci_core_services.all_oci_services[0].services[0].cidr_block
      protocol         = "6" # TCP
      destination_type = "SERVICE_CIDR_BLOCK"
      stateless        = false

      tcp_options {
        min = 443
        max = 443
      }
    }
  }

  # Egress - K8s API to Worker nodes (all TCP)
  egress_security_rules {
    destination      = var.private_subnet_cidr
    protocol         = "6" # TCP
    destination_type = "CIDR_BLOCK"
    stateless        = false
  }

  # Egress - ICMP to worker nodes (path discovery)
  egress_security_rules {
    destination      = var.private_subnet_cidr
    protocol         = "1" # ICMP
    destination_type = "CIDR_BLOCK"
    stateless        = false

    icmp_options {
      type = 3
      code = 4
    }
  }

  # Ingress - Worker nodes to K8s API endpoint (TCP/6443)
  ingress_security_rules {
    source      = var.private_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "6" # TCP
    stateless   = false

    tcp_options {
      min = 6443
      max = 6443
    }
  }

  # Ingress - Worker nodes to K8s API endpoint (TCP/12250)
  ingress_security_rules {
    source      = var.private_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "6" # TCP
    stateless   = false

    tcp_options {
      min = 12250
      max = 12250
    }
  }

  # Ingress - ICMP from worker nodes (path discovery)
  ingress_security_rules {
    source      = var.private_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "1" # ICMP
    stateless   = false

    icmp_options {
      type = 3
      code = 4
    }
  }

  # Ingress - HTTP (optional)
  dynamic "ingress_security_rules" {
    for_each = var.allow_http ? [1] : []
    content {
      source      = "0.0.0.0/0"
      source_type = "CIDR_BLOCK"
      protocol    = "6" # TCP
      stateless   = false

      tcp_options {
        min = 80
        max = 80
      }
    }
  }

  # Ingress - HTTPS (optional)
  dynamic "ingress_security_rules" {
    for_each = var.allow_https ? [1] : []
    content {
      source      = "0.0.0.0/0"
      source_type = "CIDR_BLOCK"
      protocol    = "6" # TCP
      stateless   = false

      tcp_options {
        min = 443
        max = 443
      }
    }
  }

  # Ingress - SSH from allowed CIDRs
  dynamic "ingress_security_rules" {
    for_each = var.ssh_allowed_cidrs
    content {
      source      = ingress_security_rules.value
      source_type = "CIDR_BLOCK"
      protocol    = "6" # TCP
      stateless   = false

      tcp_options {
        min = 22
        max = 22
      }
    }
  }

  # Ingress - Kubernetes API access from allowed CIDRs
  dynamic "ingress_security_rules" {
    for_each = var.k8s_api_allowed_cidrs
    content {
      source      = ingress_security_rules.value
      source_type = "CIDR_BLOCK"
      protocol    = "6" # TCP
      stateless   = false

      tcp_options {
        min = 6443
        max = 6443
      }
    }
  }

  # Ingress - NodePort range (for Ingress Controller)
  dynamic "ingress_security_rules" {
    for_each = var.enable_nodeport_access ? [1] : []
    content {
      source      = "0.0.0.0/0"
      source_type = "CIDR_BLOCK"
      protocol    = "6" # TCP
      stateless   = false

      tcp_options {
        min = var.nodeport_range_start
        max = var.nodeport_range_end
      }
    }
  }

  # Ingress - ICMP (for path discovery)
  ingress_security_rules {
    source      = var.vcn_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "1" # ICMP
    stateless   = false

    icmp_options {
      type = 3
      code = 4
    }
  }

  freeform_tags = var.common_tags
}

# Private Subnet Security List (Worker Nodes)
resource "oci_core_security_list" "private" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.cluster_name}-private-sl"

  # Egress - allow all outbound to internet (via NAT Gateway)
  egress_security_rules {
    destination      = "0.0.0.0/0"
    protocol         = "all"
    destination_type = "CIDR_BLOCK"
    stateless        = false
  }

  # Egress - Workers to Oracle Services Network (required for OKE communication)
  dynamic "egress_security_rules" {
    for_each = var.enable_service_gateway ? [1] : []
    content {
      destination      = data.oci_core_services.all_oci_services[0].services[0].cidr_block
      protocol         = "6" # TCP
      destination_type = "SERVICE_CIDR_BLOCK"
      stateless        = false
    }
  }

  # Egress - Workers to K8s API endpoint (TCP/6443)
  egress_security_rules {
    destination      = var.public_subnet_cidr
    protocol         = "6" # TCP
    destination_type = "CIDR_BLOCK"
    stateless        = false

    tcp_options {
      min = 6443
      max = 6443
    }
  }

  # Egress - Workers to K8s API endpoint (TCP/12250)
  egress_security_rules {
    destination      = var.public_subnet_cidr
    protocol         = "6" # TCP
    destination_type = "CIDR_BLOCK"
    stateless        = false

    tcp_options {
      min = 12250
      max = 12250
    }
  }

  # Egress - ICMP to public subnet (path discovery)
  egress_security_rules {
    destination      = var.public_subnet_cidr
    protocol         = "1" # ICMP
    destination_type = "CIDR_BLOCK"
    stateless        = false

    icmp_options {
      type = 3
      code = 4
    }
  }

  # Ingress - allow all from VCN (intra-cluster communication)
  ingress_security_rules {
    source      = var.vcn_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "all"
    stateless   = false
  }

  # Ingress - K8s API endpoint to workers (all TCP - required for flannel)
  ingress_security_rules {
    source      = var.public_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "6" # TCP
    stateless   = false
  }

  # Ingress - ICMP from anywhere (path discovery)
  ingress_security_rules {
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    protocol    = "1" # ICMP
    stateless   = false

    icmp_options {
      type = 3
      code = 4
    }
  }

  # Ingress - NodePort range from public subnet (for edge proxy)
  ingress_security_rules {
    source      = var.public_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "6" # TCP
    stateless   = false

    tcp_options {
      min = var.nodeport_range_start
      max = var.nodeport_range_end
    }
  }

  freeform_tags = var.common_tags
}

################################################################################
# Subnets
################################################################################

# Get Availability Domain (Jerusalem has 1 AD)
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# Public Subnet
resource "oci_core_subnet" "public" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.public_subnet_cidr
  display_name               = "${var.cluster_name}-public-subnet"
  dns_label                  = "public"
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.public.id]

  freeform_tags = var.common_tags
}

# Private Subnet
resource "oci_core_subnet" "private" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.private_subnet_cidr
  display_name               = "${var.cluster_name}-private-subnet"
  dns_label                  = "private"
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.private.id]

  freeform_tags = var.common_tags
}
