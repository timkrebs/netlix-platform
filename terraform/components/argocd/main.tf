resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.7.0"

  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }
  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

  values = [yamlencode({
    configs = {
      cm = {
        "kustomize.buildOptions" = "--load-restrictor LoadRestrictionsNone"
      }
    }
    server = {
      ingress = {
        enabled          = true
        ingressClassName = "alb"
        hostname         = "argocd.${var.environment}.${var.domain}"
        annotations = {
          "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
          "alb.ingress.kubernetes.io/target-type"      = "ip"
          "alb.ingress.kubernetes.io/certificate-arn"  = var.certificate_arn
          "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTPS\":443},{\"HTTP\":80}]"
          "alb.ingress.kubernetes.io/ssl-redirect"     = "443"
          "alb.ingress.kubernetes.io/backend-protocol" = "HTTP"
          "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
          "external-dns.alpha.kubernetes.io/hostname"  = "argocd.${var.environment}.${var.domain}"
        }
      }
    }
    extraObjects = [
      {
        apiVersion = "argoproj.io/v1alpha1"
        kind       = "Application"
        metadata = {
          name      = "netlix-app"
          namespace = "argocd"
        }
        spec = {
          project = "default"
          source = {
            repoURL        = var.gitops_repo_url
            targetRevision = "HEAD"
            path           = "app/overlays/${var.environment}"
          }
          destination = {
            server    = "https://kubernetes.default.svc"
            namespace = var.target_namespace
          }
          syncPolicy = {
            automated = {
              prune    = true
              selfHeal = true
            }
            syncOptions = ["CreateNamespace=true"]
          }
        }
      }
    ]
  })]
}
