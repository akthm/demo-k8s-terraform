# ==============================================================================
# Cluster Services Module - Outputs (Simplified)
# ==============================================================================

output "argocd_namespace" {
  description = "Namespace where ArgoCD is deployed"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "nginx_ingress_namespace" {
  description = "Namespace where NGINX Ingress Controller is deployed"
  value       = kubernetes_namespace.nginx_ingress.metadata[0].name
}

output "argocd_admin_password_command" {
  description = "Command to retrieve ArgoCD admin password"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "nginx_loadbalancer_command" {
  description = "Command to get LoadBalancer IP/hostname"
  value       = "kubectl -n ingress-nginx get svc nginx-ingress-controller-ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' || kubectl -n ingress-nginx get svc nginx-ingress-controller-ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
}

output "argocd_url" {
  description = "ArgoCD access URL (after LoadBalancer is provisioned)"
  value       = "http://<LoadBalancer-IP-or-Hostname>/argo"
}
