################################################################################
# OCI Network Load Balancer Module - Variables
################################################################################

variable "compartment_id" {
  description = "OCI Compartment OCID"
  type        = string
}

variable "lb_name" {
  description = "Display name for the load balancer"
  type        = string
}

variable "public_subnet_id" {
  description = "OCID of the public subnet for the load balancer"
  type        = string
}

variable "backend_ips" {
  description = "List of backend IP addresses (worker node private IPs)"
  type        = list(string)
  default     = []
}

variable "http_nodeport" {
  description = "NodePort for HTTP traffic"
  type        = number
  default     = 30080
}

variable "https_nodeport" {
  description = "NodePort for HTTPS traffic"
  type        = number
  default     = 30443
}

variable "reserved_ip_id" {
  description = "OCID of reserved public IP (optional, leave empty for ephemeral)"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
