variable "environment" { type = string }
variable "aws_region"  { type = string }
variable "region" { type = string }

variable "owner" {
  type        = string
  description = "Owner used for naming/labels."
}

variable "app_name" {
  type        = string
  description = "App name used for naming/labels."
}

variable "common_tags" {
  type        = map(string)
  description = "Tags to apply to AWS resources."
  default     = {}
}

variable "vpc_cidrs" { type = list(string) }
variable "ha" { type = bool }

variable "cluster_version" { type = string }
variable "node_type" { type = string }
