## DISABLED FOR STAGING  ( MANUAL PROVISION REQUIRED )
# resource "null_resource" "external_secrets_cluster_store" {
#   provisioner "local-exec" {
#     command = <<-EOT
#       kubectl apply -f - <<'EOF'
# apiVersion: external-secrets.io/v1beta1
# kind: ClusterSecretStore
# metadata:
#   name: aws-secrets-manager
# spec:
#   provider:
#     aws:
#       service: SecretsManager
#       region: ${var.aws_region}
#       auth:
#         jwt:
#           serviceAccountRef:
#             name: external-secrets-controller
#             namespace: external-secrets
# EOF
#     EOT

#     environment = {
#       KUBECONFIG = "/tmp/kubeconfig-${var.cluster_name}"
#     }
#   }

#   # This must wait until the ESO Helm chart is fully installed
#   # and the CRDs (like 'ClusterSecretStore') are available to the API.
#   depends_on = [
#     helm_release.external_secrets,
#     helm_release.nginx_ingress_controller
#   ]
# }