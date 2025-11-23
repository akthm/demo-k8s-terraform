/**
 * ==============================================================================
 * Cluster Services - Simplified Bootstrap
 * ==============================================================================
 *
 * This module bootstraps the minimal services needed for GitOps:
 * 1. NGINX Ingress Controller - Routes HTTP traffic via AWS NLB
 * 2. ArgoCD - GitOps continuous deployment from Git
 *
 * Strategy: Terraform bootstraps these two services, then ArgoCD manages
 * everything else via Git repositories (App-of-Apps pattern).
 * ==============================================================================
 */

# ===============================================================================
# Kubernetes Namespaces
# ===============================================================================

resource "kubernetes_namespace" "nginx_ingress" {
  metadata {
    name = "ingress-nginx"
    labels = {
      "app.kubernetes.io/name" = "ingress-nginx"
    }
  }
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      "app.kubernetes.io/name" = "argocd"
    }
  }
}


# ===============================================================================
# 1. NGINX Ingress Controller
# ===============================================================================
# Exposes services via AWS Network Load Balancer
# Provides path-based routing for ArgoCD and other services

resource "helm_release" "nginx_ingress_controller" {
  name       = "nginx-ingress-controller"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = kubernetes_namespace.nginx_ingress.metadata[0].name
  version    = "4.10.0"

  values = [
    yamlencode({
      controller = {
        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
          }
        }
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

  depends_on = [kubernetes_namespace.nginx_ingress]
}

# ===============================================================================
# 2. ArgoCD
# ===============================================================================
# GitOps continuous deployment engine
# Manages all application deployments from Git after bootstrap

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = var.argocd_version

  values = [
    yamlencode({
      server = {
        ingress = {
          enabled = false # Using custom path-based ingress below
        }
        extraArgs = [
          "--basehref=/argo",
          "--rootpath=/argo",
          "--insecure"  # Disable TLS/HTTPS redirect
        ]
        replicas = 2
        resources = {
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
        }
      }

      applicationController = {
        replicas = 2
        resources = {
          limits = {
            cpu    = "1000m"
            memory = "1Gi"
          }
          requests = {
            cpu    = "250m"
            memory = "512Mi"
          }
        }
      }

      repoServer = {
        replicas = 2
        resources = {
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
        }
      }

      redis = {
        enabled = true
      }

      configs = {
        secret = {
          createSecret = true
        }
        params = {
          "server.basehref" = "/argo"
          "server.rootpath" = "/argo"
          "server.insecure" = "true"  # Allow HTTP access without TLS
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.argocd,
    helm_release.nginx_ingress_controller
  ]
}

# Wait for ArgoCD CRDs to be registered in the API server
resource "time_sleep" "wait_for_argocd_crds" {
  depends_on = [helm_release.argocd]

  create_duration = "60s"
}

# ===============================================================================
# ArgoCD Path-Based Ingress
# ===============================================================================
# Routes http://LoadBalancer-IP/argo to ArgoCD UI
# No DNS required - accessible immediately after deployment

resource "kubernetes_manifest" "argocd_ingress" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "argocd-ingress"
      namespace = kubernetes_namespace.argocd.metadata[0].name
      annotations = {
        # No rewrite needed - ArgoCD is configured with --basehref=/argo
        "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP"
        "nginx.ingress.kubernetes.io/ssl-redirect"     = "false"
      }
    }
    spec = {
      ingressClassName = "nginx"
      rules = [
        {
          http = {
            paths = [
              {
                path     = "/argo"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = "argocd-server"
                    port = {
                      number = 80
                    }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  }

  depends_on = [helm_release.argocd]
}

# ===============================================================================
# ArgoCD Git Repository Credentials
# ===============================================================================
# Allows ArgoCD to pull from private Git repositories

resource "kubernetes_secret" "argocd_repo_credentials" {
  metadata {
    name      = "argocd-repo-creds"
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  type = "Opaque"

  data = {
    type     = base64encode("git")
    url      = base64encode(var.argocd_repo_url)
    password = base64encode(var.git_token)
    username = base64encode("git")
  }

  depends_on = [helm_release.argocd]
}

# ===============================================================================
# ArgoCD Root Application (App-of-Apps)
# ===============================================================================
# Bootstrap application that manages all other applications from Git
# This enables the GitOps workflow where Git is the source of truth
# Using null_resource + kubectl to avoid CRD timing issues during plan

resource "null_resource" "argocd_root_app" {
  triggers = {
    repo_url        = var.argocd_repo_url
    repo_path       = var.argocd_repo_path
    target_revision = var.argocd_target_revision
    manifest_sha    = sha256(jsonencode({
      apiVersion = "argoproj.io/v1alpha1"
      kind       = "Application"
      metadata = {
        name      = "root-app"
        namespace = "argocd"
      }
    }))
  }

  provisioner "local-exec" {
    command = <<-EOT
      cat <<EOF | kubectl apply -f -
      apiVersion: argoproj.io/v1alpha1
      kind: Application
      metadata:
        name: root-app
        namespace: argocd
        finalizers:
        - resources-finalizer.argocd.argoproj.io
      spec:
        project: default
        source:
          repoURL: ${var.argocd_repo_url}
          targetRevision: ${var.argocd_target_revision}
          path: ${var.argocd_repo_path}
        destination:
          server: https://kubernetes.default.svc
          namespace: default
        syncPolicy:
          automated:
            prune: true
            selfHeal: true
          syncOptions:
          - CreateNamespace=true
          - PrunePropagationPolicy=background
          retry:
            limit: 5
            backoff:
              duration: 5s
              factor: 2
              maxDuration: 3m
      EOF
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kubectl delete application root-app -n argocd --ignore-not-found=true"
  }

  depends_on = [
    helm_release.argocd,
    kubernetes_secret.argocd_repo_credentials,
    time_sleep.wait_for_argocd_crds
  ]
}
