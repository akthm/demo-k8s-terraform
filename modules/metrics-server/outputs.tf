# Metrics Server Module Outputs

output "metrics_server_deployed" {
  description = "Whether metrics-server was successfully deployed"
  value       = var.use_helm ? (length(helm_release.metrics_server) > 0) : (length(null_resource.metrics_server_manifest) > 0)
}

output "deployment_method" {
  description = "Installation method used (helm or manifest)"
  value       = var.use_helm ? "helm" : "manifest"
}

output "platform" {
  description = "Platform metrics-server was deployed for"
  value       = var.platform
}
