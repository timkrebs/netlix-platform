resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.chart_version
  wait             = true
  timeout          = 300

  set {
    name  = "crds.enabled"
    value = "true"
  }
}
