resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.7.0"

  set { name = "server.service.type"              value = "LoadBalancer" }
  set { name = "configs.params.server\\.insecure" value = "true" }
}
