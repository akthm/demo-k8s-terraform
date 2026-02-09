variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "ip_address_pool" {
  description = "MetalLB IP address pool configuration"
  type = object({
    name      = string
    protocol  = string
    addresses = list(string)
  })
  default = {
    name      = "default"
    protocol  = "layer2"
    addresses = ["172.18.255.200-172.18.255.250"]
  }
}

variable "metallb_version" {
  description = "MetalLB Helm chart version"
  type        = string
  default     = "0.14.5"
}
