# This module is retained only for the Stacks `removed` block to destroy
# existing resources.  Delete this directory after the destroy run completes.

resource "kubernetes_namespace_v1" "datadog" {
  metadata {
    name = "datadog"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "helm_release" "datadog_operator" {
  name             = "datadog-operator"
  namespace        = kubernetes_namespace_v1.datadog.metadata[0].name
  repository       = "https://helm.datadoghq.com"
  chart            = "datadog-operator"
  version          = "2.1.0"
  create_namespace = false

  set {
    name  = "replicaCount"
    value = "1"
  }
}
