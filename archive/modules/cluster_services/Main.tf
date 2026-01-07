/**
 * ==============================================================================
 * Cluster Services - Helm Releases & Kubernetes Manifests
 * ==============================================================================
 */

resource "kubernetes_namespace" "nginx_ingress" {
  metadata {
    name = "ingress-nginx"
  }
}

// Create the namespace for ArgoCD
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

// Create the namespace for External Secrets Operator
resource "kubernetes_namespace" "external_secrets" {
  metadata {
    name = "external-secrets"
  }
}

/**
 * ------------------------------------------------------------------------------
 * 1. Install NGINX Ingress Controller
 * ------------------------------------------------------------------------------
 * Features:
 * - Ingress class: "nginx"
 * - Exposed via LoadBalancer service (AWS auto-creates one NLB per cluster)
 * - Low overhead, runs as Deployment in cluster
 * - No IAM roles needed
 */
resource "helm_release" "nginx_ingress_controller" {
  name       = "nginx-ingress-controller"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = kubernetes_namespace.nginx_ingress.metadata[0].name
  version    = "4.10.0" # Pin your chart version!

  # Pass values to the Helm chart
  values = [
    yamlencode({
      controller = {
        # Use a single LoadBalancer service for the NGINX ingress
        service = {
          type = "LoadBalancer"
          # Optional: pin to specific AWS NLB configuration
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
          }
        }
        # Enable metrics for monitoring
        metrics = {
          enabled = true
        }
        # Pod resource requests (adjust for your workload)
        resources = {
          limits = {
            cpu    = "200m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.nginx_ingress
  ]
}

/**
 * ------------------------------------------------------------------------------
 * 2. Install ArgoCD
 * ------------------------------------------------------------------------------
 *
 * This installs the ArgoCD controller with NGINX Ingress.
 */    # DISABLED FOR STAGING  ( MANUAL PROVISION REQUIRED )
# resource "helm_release" "argocd" {
#   name       = "argocd"
#   repository = "https://argoproj.github.io/argo-helm"
#   chart      = "argo-cd"
#   namespace  = kubernetes_namespace.argocd.metadata[0].name
#   version    = "5.51.0" # Pin your chart version!

#   # Configure ArgoCD with NGINX ingress
#   values = [
#     yamlencode({
#       server = {
#         # Enable NGINX Ingress for ArgoCD
#         ingress = {
#           enabled = true
#           ingressClassName = "nginx"
#           # Update with your domain
#           hosts = ["argocd.your-domain.com"]
#           annotations = {
#             # NGINX-specific annotations
#             "cert-manager.io/cluster-issuer" = "letsencrypt-prod" # If using cert-manager
#           }
#           # Optional TLS
#           # tls = [{
#           #   secretName = "argocd-tls"
#           #   hosts = ["argocd.your-domain.com"]
#           # }]
#         }
#       }
#     })
#   ]

#   depends_on = [
#     kubernetes_namespace.argocd,
#     helm_release.nginx_ingress_controller # Ensure NGINX is running first
#   ]
# }

/**
 * ------------------------------------------------------------------------------
 * 3. Install External Secrets Operator (ESO)
 * ------------------------------------------------------------------------------
 *
  * Uses the IAM role created in 'iam_external_secrets.tf'
 */    #  DISABLED FOR STAGING 
# resource "helm_release" "external_secrets" {
#   name       = "external-secrets"
#   repository = "https://charts.external-secrets.io"
#   chart      = "external-secrets"
#   namespace  = kubernetes_namespace.external_secrets.metadata[0].name
#   version    = "0.9.11" # Pin your chart version!

#   values = [
#     yamlencode({
#       # Tell the chart to create a service account
#       serviceAccount = {
#         create = true
#         name   = "external-secrets-controller"
#         # THIS IS THE MAGIC FOR IRSA: Annotate the SA with the IAM role ARN
#         annotations = {
#           "eks.amazonaws.com/role-arn" = aws_iam_role.external_secrets.arn
#         }
#       }
#       # This is important! This 'serviceAccountName' must match the 'name' above.
#       # It tells the controller Deployment to USE the Service Account we are creating.
#       serviceAccountName = "external-secrets-controller"
#     })
#   ]

#   depends_on = [
#     aws_iam_role_policy_attachment.external_secrets,
#     kubernetes_namespace.external_secrets,
#     helm_release.nginx_ingress_controller
#   ]
# }