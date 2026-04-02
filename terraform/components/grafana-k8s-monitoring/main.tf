# Read the Grafana Cloud API token from a pre-existing K8s secret.
# This avoids flowing ephemeral varset values through Stacks component inputs.
#
# Create the secret before deploying:
#   kubectl create secret generic grafana-cloud-credentials \
#     -n kube-system \
#     --from-literal=token=glc_YOUR_TOKEN_HERE
data "kubernetes_secret_v1" "grafana_credentials" {
  metadata {
    name      = "grafana-cloud-credentials"
    namespace = "kube-system"
  }
}

locals {
  grafana_token = data.kubernetes_secret_v1.grafana_credentials.data["token"]

}

resource "helm_release" "k8s_monitoring" {
  name             = "grafana-k8s-monitoring"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "k8s-monitoring"
  version          = "^3"
  namespace        = var.namespace
  create_namespace = true
  atomic           = true
  timeout          = 600

  values = [templatefile("${path.module}/values.yaml", {
    cluster_name = var.cluster_name
  })]

  set {
    name  = "cluster.name"
    value = var.cluster_name
  }

  # ── Prometheus destination ───────────────────────────────────────────────

  set {
    name  = "destinations[0].url"
    value = var.prometheus_url
  }

  set {
    name  = "destinations[0].auth.username"
    value = var.prometheus_username
  }

  set_sensitive {
    name  = "destinations[0].auth.password"
    value = local.grafana_token
  }

  # ── Loki destination ────────────────────────────────────────────────────

  set {
    name  = "destinations[1].url"
    value = var.loki_url
  }

  set {
    name  = "destinations[1].auth.username"
    value = var.loki_username
  }

  set_sensitive {
    name  = "destinations[1].auth.password"
    value = local.grafana_token
  }

  # ── OTLP destination ────────────────────────────────────────────────────

  set {
    name  = "destinations[2].url"
    value = var.otlp_url
  }

  set {
    name  = "destinations[2].auth.username"
    value = var.otlp_username
  }

  set_sensitive {
    name  = "destinations[2].auth.password"
    value = local.grafana_token
  }

  # ── Pyroscope destination ───────────────────────────────────────────────

  set {
    name  = "destinations[3].url"
    value = var.pyroscope_url
  }

  set {
    name  = "destinations[3].auth.username"
    value = var.pyroscope_username
  }

  set_sensitive {
    name  = "destinations[3].auth.password"
    value = local.grafana_token
  }

  # ── OpenCost ────────────────────────────────────────────────────────────

  set {
    name  = "clusterMetrics.opencost.opencost.exporter.defaultClusterId"
    value = var.cluster_name
  }

  set {
    name  = "clusterMetrics.opencost.opencost.prometheus.external.url"
    value = trimsuffix(var.prometheus_url, "/push")
  }

}
