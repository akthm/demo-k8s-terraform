# DISABLED FOR STAGING ( MANUAL PROVISION REQUIRED )
# resource "null_resource" "argocd_app_of_apps" {
#   provisioner "local-exec" {
#     command = <<-EOT
#       kubectl apply -f - <<'EOF'
# apiVersion: argoproj.io/v1alpha1
# kind: Application
# metadata:
#   name: root-apps
#   namespace: argocd
#   finalizers:
#   - resources-finalizer.argocd.argoproj.io
# spec:
#   project: default
#   source:
#     repoURL: ${var.argocd_app_of_apps_repo_url}
#     targetRevision: HEAD
#     path: ${var.argocd_app_of_apps_repo_path}
#   destination:
#     server: https://kubernetes.default.svc
#     namespace: default
#   syncPolicy:
#     automated:
#       prune: true
#       selfHeal: true
#     syncOptions:
#     - CreateNamespace=true
# EOF
#     EOT

#     environment = {
#       KUBECONFIG = "/tmp/kubeconfig-${var.cluster_name}"
#     }
#   }

#   # This must wait until the ArgoCD Helm chart is fully installed
#   # and the CRDs (like 'Application') are available to the API.
#   depends_on = [
#     helm_release.argocd,
#     helm_release.nginx_ingress_controller
#   ]
# }