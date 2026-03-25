resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.7.0"

  set {
    name  = "server.service.type"
    value = "LoadBalancer"
  }
  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

  values = [yamlencode({
    server = {
      additionalApplications = [
        {
          name      = "netlix-app"
          namespace = "argocd"
          project   = "default"
          source = {
            repoURL        = var.gitops_repo_url
            targetRevision  = "HEAD"
            path           = "apps/netlix"
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
      ]
    }
  })]
}
