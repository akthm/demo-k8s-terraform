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

locals {
  owner    = var.owner
  app_name = var.app_name
}

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

# Cleanup NGINX namespace resources before destruction
resource "null_resource" "nginx_namespace_cleanup" {
  triggers = {
    namespace = kubernetes_namespace.nginx_ingress.metadata[0].name
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set +e
      echo "=== Force cleaning NGINX namespace ==="
      
      # Delete all resources in namespace with force
      kubectl delete all --all -n ingress-nginx --grace-period=0 --force --timeout=30s 2>/dev/null || true
      
      # Remove finalizers only from resources that commonly have them (skip events, configmaps, etc.)
      # Events don't have finalizers and iterating through them causes long delays
      for resource in secrets serviceaccounts persistentvolumeclaims roles rolebindings; do
        for item in $(kubectl get $resource -n ingress-nginx -o name 2>/dev/null || true); do
          kubectl patch $item -n ingress-nginx -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        done
      done
      
      # Force delete the namespace
      kubectl delete namespace ingress-nginx --grace-period=0 --force --timeout=10s 2>/dev/null || true
      
      # Remove namespace finalizers if still stuck
      kubectl patch namespace ingress-nginx -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
      
      echo "=== NGINX namespace cleanup completed ==="
    EOT
  }

  depends_on = [
    helm_release.nginx_ingress_controller
  ]
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      "app.kubernetes.io/name" = "argocd"
    }
  }
}

# Cleanup ArgoCD namespace resources before destruction
resource "null_resource" "argocd_namespace_cleanup" {
  triggers = {
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set +e
      echo "=== Force cleaning ArgoCD namespace ==="
      
      # Remove finalizers from all Applications first
      for app in $(kubectl get applications -n argocd -o name 2>/dev/null || true); do
        kubectl patch $app -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
      done
      
      # Force delete all Applications
      kubectl delete applications --all -n argocd --grace-period=0 --force --timeout=10s 2>/dev/null || true
      
      # Remove finalizers from all AppProjects
      for proj in $(kubectl get appprojects -n argocd -o name 2>/dev/null || true); do
        kubectl patch $proj -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
      done
      
      # Force delete all AppProjects
      kubectl delete appprojects --all -n argocd --grace-period=0 --force --timeout=10s 2>/dev/null || true
      
      # Remove finalizers from ExternalSecrets
      for es in $(kubectl get externalsecrets -n argocd -o name 2>/dev/null || true); do
        kubectl patch $es -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
      done
      kubectl delete externalsecrets --all -n argocd --grace-period=0 --force --timeout=10s 2>/dev/null || true
      
      # Delete all remaining resources in namespace with force
      kubectl delete all --all -n argocd --grace-period=0 --force --timeout=30s 2>/dev/null || true
      
      # Remove finalizers only from resources that commonly have them (skip events, configmaps, etc.)
      # Events don't have finalizers and iterating through them causes long delays
      for resource in secrets serviceaccounts persistentvolumeclaims roles rolebindings; do
        for item in $(kubectl get $resource -n argocd -o name 2>/dev/null || true); do
          kubectl patch $item -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        done
      done
      
      # Force delete the namespace
      kubectl delete namespace argocd --grace-period=0 --force --timeout=10s 2>/dev/null || true
      
      # Remove namespace finalizers if still stuck
      kubectl patch namespace argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
      
      echo "=== ArgoCD namespace cleanup completed ==="
    EOT
  }

  depends_on = [
    null_resource.argocd_root_app,
    helm_release.argocd,
    kubernetes_secret.argocd_repo_credentials
  ]
}


# ===============================================================================
# 1. NGINX Ingress Controller
# ===============================================================================
# Exposes services via AWS Network Load Balancer
# Provides path-based routing for ArgoCD and other services

locals {
  is_kind = var.platform == "kind"
  is_oke  = var.platform == "oke"
  is_eks  = var.platform == "eks"
  # Use LoadBalancer if MetalLB is enabled, otherwise use NodePort for Kind
  kind_use_loadbalancer = var.use_metallb
}

# OKE-specific NGINX config (NodePort for edge proxy pattern)
locals {
  oke_nginx_values = yamlencode({
    controller = {
      service = {
        type = var.nginx_service_type
        nodePorts = var.nginx_service_type == "NodePort" ? {
          http  = var.nginx_http_nodeport
          https = var.nginx_https_nodeport
        } : null
      }
      resources = {
        limits   = { cpu = "200m", memory = "512Mi" }
        requests = { cpu = "100m", memory = "256Mi" }
      }
    }
  })
}

resource "helm_release" "nginx_ingress_controller" {
  name       = "nginx-ingress-controller"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = kubernetes_namespace.nginx_ingress.metadata[0].name
  version    = "4.10.0"

  # Increase timeout for Kind clusters
  timeout = 300 # 5 minutes
  wait    = true

  values = [local.is_kind ? (
    # Kind cluster with MetalLB LoadBalancer
    local.kind_use_loadbalancer ? yamlencode({
      controller = {
        service = {
          type = "LoadBalancer"
        }
        nodeSelector = {
          ingress-ready = "true"
        }
        # Important on kind to allow scheduling on control-plane nodes
        tolerations = [
          {
            key      = "node-role.kubernetes.io/control-plane"
            operator = "Equal"
            effect   = "NoSchedule"
          },
          {
            key      = "node-role.kubernetes.io/master"
            operator = "Equal"
            effect   = "NoSchedule"
          }
        ]
        resources = {
          limits   = { cpu = "200m", memory = "512Mi" }
          requests = { cpu = "100m", memory = "256Mi" }
        }
      }
    }) :
    # Kind cluster with NodePort (default, no MetalLB)
    yamlencode({
      controller = {
        service = {
          type = "NodePort"
        }
        hostPort = {
          enabled = true
          ports = {
            http  = 80
            https = 443
          }
        }
        nodeSelector = {
          ingress-ready = "true"
        }
        # Important on kind to allow scheduling on control-plane nodes
        tolerations = [
          {
            key      = "node-role.kubernetes.io/control-plane"
            operator = "Equal"
            effect   = "NoSchedule"
          },
          {
            key      = "node-role.kubernetes.io/master"
            operator = "Equal"
            effect   = "NoSchedule"
          }
        ]
        resources = {
          limits   = { cpu = "200m", memory = "512Mi" }
          requests = { cpu = "100m", memory = "256Mi" }
        }
      }
    })
    ) : (
    # OKE cluster (OCI) - NodePort for edge proxy pattern or LoadBalancer
    local.is_oke ? local.oke_nginx_values :
    # EKS/Cloud cluster with AWS NLB
    yamlencode({
      controller = {
        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
          }
        }
        resources = {
          limits   = { cpu = "200m", memory = "512Mi" }
          requests = { cpu = "100m", memory = "256Mi" }
        }
      }
  }))]

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

  # Increase timeout for slow Kind clusters
  timeout       = 600 # 10 minutes
  wait          = true
  wait_for_jobs = true

  # Allow deployment to succeed even if some pods are slow to start
  atomic          = false
  cleanup_on_fail = false
  replace         = false
  force_update    = false
  recreate_pods   = false

  values = [
    yamlencode({
      server = {
        ingress = {
          enabled = false # Using custom path-based ingress below
        }
        extraArgs =  local.is_kind ? [
          "--insecure" # Disable TLS/HTTPS redirect
        ] : []
        autoscaling = {
          enabled                        = true
          minReplicas                    = 1
          maxReplicas                    = local.is_kind ? 2 : 4
          targetCPUUtilizationPercentage = 50
        }
        resources = {
          limits = {
            cpu    = local.is_kind ? "200m" : "500m"
            memory = local.is_kind ? "256Mi" : "512Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
        }
      }

      applicationController = {
        autoscaling = {
          enabled                        = true
          minReplicas                    = 1
          maxReplicas                    = local.is_kind ? 1 : 3
          targetCPUUtilizationPercentage = 50
        }
        resources = {
          limits = {
            cpu    = local.is_kind ? "500m" : "1000m"
            memory = local.is_kind ? "512Mi" : "1Gi"
          }
          requests = {
            cpu    = "250m"
            memory = "512Mi"
          }
        }
      }

      repoServer = {
        replicas = local.is_kind ? 1 : 2 # Single replica for Kind
        resources = {
          limits = {
            cpu    = local.is_kind ? "200m" : "500m"
            memory = local.is_kind ? "256Mi" : "512Mi"
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
          # "server.basehref" = "/argo" Disabled as it causes issues with some versions
          # "server.rootpath" = "/argo"
          "server.insecure" = local.is_kind ? "true" : "false" # Allow HTTP access without TLS on local
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
resource "null_resource" "wait_for_argocd_crds" {
  depends_on = [helm_release.argocd]

  provisioner "local-exec" {
    when    = create
    command = <<-EOT
      set -e
      echo "Waiting for Argo CD CRDs..."
      kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=120s
      kubectl wait --for=condition=Established crd/appprojects.argoproj.io --timeout=120s
      echo "Argo CD CRDs are ready"
    EOT
  }
}


# ===============================================================================
# ArgoCD Path-Based Ingress
# ===============================================================================
# Routes http://LoadBalancer-IP/argo or http://platform.<IP>.nip.io/argo to ArgoCD UI
# Supports both path-only (no host) and nip.io domain-based routing
#
# NOTE: Commented out - ArgoCD ingress will be provisioned by ArgoCD itself via GitOps

# locals {
#   # Use nip.io domain if ingress_domain is set and not localhost
#   use_domain_routing = var.ingress_domain != "localhost" && var.ingress_domain != ""
#   
#   # Ingress rule for path-only routing (no host restriction)
#   argocd_ingress_rule_path_only = {
#     http = {
#       paths = [
#         {
#           path     = "/argo"
#           pathType = "Prefix"
#           backend = {
#             service = {
#               name = "argocd-server"
#               port = {
#                 number = 80
#               }
#             }
#           }
#         }
#       ]
#     }
#   }
#   
#   # Ingress rule for domain-based routing (e.g., platform.172.18.255.200.nip.io)
#   argocd_ingress_rule_with_host = {
#     host = var.ingress_domain
#     http = {
#       paths = [
#         {
#           path     = "/argo"
#           pathType = "Prefix"
#           backend = {
#             service = {
#               name = "argocd-server"
#               port = {
#                 number = 80
#               }
#             }
#           }
#         }
#       ]
#     }
#   }
# }

# # Ingress without host (path-only routing) - default behavior
# resource "kubernetes_manifest" "argocd_ingress" {
#   count = local.use_domain_routing ? 0 : 1
#   
#   manifest = {
#     apiVersion = "networking.k8s.io/v1"
#     kind       = "Ingress"
#     metadata = {
#       name      = "argocd-ingress"
#       namespace = kubernetes_namespace.argocd.metadata[0].name
#       annotations = {
#         "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP"
#         "nginx.ingress.kubernetes.io/ssl-redirect"     = "false"
#       }
#     }
#     spec = {
#       ingressClassName = "nginx"
#       rules            = [local.argocd_ingress_rule_path_only]
#     }
#   }

#   depends_on = [helm_release.argocd]
# }

# # Ingress with host (nip.io domain-based routing)
# resource "kubernetes_manifest" "argocd_ingress_with_host" {
#   count = local.use_domain_routing ? 1 : 0
#   
#   manifest = {
#     apiVersion = "networking.k8s.io/v1"
#     kind       = "Ingress"
#     metadata = {
#       name      = "argocd-ingress"
#       namespace = kubernetes_namespace.argocd.metadata[0].name
#       annotations = {
#         "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP"
#         "nginx.ingress.kubernetes.io/ssl-redirect"     = "false"
#       }
#     }
#     spec = {
#       ingressClassName = "nginx"
#       rules            = [local.argocd_ingress_rule_with_host]
#     }
#   }

#   depends_on = [helm_release.argocd]
# }

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
    manifest_sha = sha256(jsonencode({
      apiVersion = "argoproj.io/v1alpha1"
      kind       = "Application"
      metadata = {
        name      = "root-app"
        namespace = "argocd"
      }
    }))
  }

  provisioner "local-exec" {
    when    = create
    command = <<-EOT
      kubectl apply -f - <<'EOF'
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
    command = <<-EOT
      set -e
      # Try graceful delete first (with timeout)
      kubectl delete application root-app -n argocd --wait=true --timeout=30s --ignore-not-found=true 2>/dev/null || {
        echo "Graceful delete timed out, forcing deletion..."
        # Remove finalizers to force immediate deletion
        kubectl patch application root-app -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        kubectl delete application root-app -n argocd --ignore-not-found=true --grace-period=0 --force 2>/dev/null || true
      }
      echo "ArgoCD root-app cleanup completed"
    EOT
  }

  depends_on = [
    helm_release.argocd,
    kubernetes_secret.argocd_repo_credentials,
    null_resource.wait_for_argocd_crds
  ]
}

# ===============================================================================
# Metrics Server
# ===============================================================================
# Provides resource metrics API for kubectl top and HPA

# module "metrics_server" {
#   source = "../metrics-server"

#   platform           = var.platform
#   cluster_name       = var.app_name # Using app_name as cluster identifier
#   use_helm           = var.platform != "kind" # Use Helm for OKE/EKS, manifest for Kind
#   cluster_trigger_id = var.cluster_trigger_id

#   depends_on = [
#     helm_release.nginx_ingress_controller
#   ]
# }
