# ─── Namespace ────────────────────────────────────────────────────────────

locals {
  grafana_admin_secret = "grafana-admin"
  grafana_host         = "grafana.${var.environment}.${var.domain}"
}

resource "kubernetes_namespace" "observability" {
  metadata {
    name = "observability"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "netlix.dev/component"         = "observability"
    }
  }
}

# ─── Grafana admin credentials synced from Vault via VSO ──────────────────
# VSO connects using the default VaultConnection+VaultAuth installed by the
# vso component — `secret/netlix/grafana` is readable under the netlix-vso
# policy (wildcard `secret/data/netlix/*`).

resource "kubectl_manifest" "vault_static_secret_grafana" {
  yaml_body = yamlencode({
    apiVersion = "secrets.hashicorp.com/v1beta1"
    kind       = "VaultStaticSecret"
    metadata = {
      name      = "grafana-admin"
      namespace = kubernetes_namespace.observability.metadata[0].name
    }
    spec = {
      type         = "kv-v2"
      mount        = "secret"
      path         = "netlix/grafana"
      namespace    = var.environment
      refreshAfter = "60s"
      destination = {
        name   = local.grafana_admin_secret
        create = true
      }
    }
  })

  depends_on = [kubernetes_namespace.observability]
}

# ─── kube-prometheus-stack (Prometheus + Grafana + AlertManager) ──────────

resource "helm_release" "kube_prometheus_stack" {
  name       = "kps"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.kube_prometheus_stack_version
  wait       = true
  timeout    = 900

  values = [yamlencode({
    # Pick up ServiceMonitors / PodMonitors / Rules from any namespace
    # (Vault in `vault`, shop services + Envoy in `consul`).
    prometheus = {
      prometheusSpec = {
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        ruleSelectorNilUsesHelmValues           = false
        probeSelectorNilUsesHelmValues          = false
        retention                               = var.prometheus_retention
        storageSpec = {
          volumeClaimTemplate = {
            spec = {
              storageClassName = var.storage_class
              accessModes      = ["ReadWriteOnce"]
              resources        = { requests = { storage = var.prometheus_storage_size } }
            }
          }
        }
      }
    }

    alertmanager = {
      enabled = true
      alertmanagerSpec = {
        storage = {
          volumeClaimTemplate = {
            spec = {
              storageClassName = var.storage_class
              accessModes      = ["ReadWriteOnce"]
              resources        = { requests = { storage = "5Gi" } }
            }
          }
        }
      }
      # Deployed but silent — receivers intentionally empty for the
      # first iteration. Dashboards-first rollout; routing comes later.
      config = {
        route = {
          receiver        = "null"
          group_by        = ["alertname", "namespace"]
          group_wait      = "30s"
          group_interval  = "5m"
          repeat_interval = "12h"
        }
        receivers = [
          { name = "null" }
        ]
      }
    }

    kubeStateMetrics = { enabled = true }
    nodeExporter     = { enabled = true }

    grafana = {
      enabled = true

      admin = {
        existingSecret = local.grafana_admin_secret
        userKey        = "username"
        passwordKey    = "password"
      }

      persistence = {
        enabled          = true
        storageClassName = var.storage_class
        size             = var.grafana_storage_size
      }

      # Sidecar: auto-load ConfigMaps labeled `grafana_dashboard=1` as dashboards.
      sidecar = {
        dashboards = {
          enabled          = true
          label            = "grafana_dashboard"
          labelValue       = "1"
          searchNamespace  = "ALL"
          folderAnnotation = "grafana_folder"
          provider = {
            foldersFromFilesStructure = true
          }
        }
        datasources = {
          enabled = true
          label   = "grafana_datasource"
        }
      }

      # Loki as an additional datasource alongside the stack's default Prometheus.
      additionalDataSources = [
        {
          name      = "Loki"
          type      = "loki"
          url       = "http://loki-gateway.${kubernetes_namespace.observability.metadata[0].name}.svc.cluster.local"
          access    = "proxy"
          isDefault = false
        }
      ]

      # Remote dashboards — fetched on boot by the chart's init container.
      dashboardProviders = {
        "dashboardproviders.yaml" = {
          apiVersion = 1
          providers = [{
            name            = "default"
            orgId           = 1
            folder          = ""
            type            = "file"
            disableDeletion = false
            editable        = true
            options         = { path = "/var/lib/grafana/dashboards/default" }
          }]
        }
      }

      dashboards = {
        default = {
          vault = {
            gnetId     = 12904
            revision   = 1
            datasource = "Prometheus"
          }
          kubernetes-cluster = {
            gnetId     = 15760
            revision   = 36
            datasource = "Prometheus"
          }
          loki-logs = {
            gnetId     = 13639
            revision   = 2
            datasource = "Loki"
          }
          node-exporter = {
            gnetId     = 1860
            revision   = 37
            datasource = "Prometheus"
          }
        }
      }

      ingress = {
        enabled          = true
        ingressClassName = "alb"
        hosts            = [local.grafana_host]
        annotations = {
          "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
          "alb.ingress.kubernetes.io/target-type"      = "ip"
          "alb.ingress.kubernetes.io/certificate-arn"  = var.certificate_arn
          "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTPS\":443},{\"HTTP\":80}]"
          "alb.ingress.kubernetes.io/ssl-redirect"     = "443"
          "alb.ingress.kubernetes.io/backend-protocol" = "HTTP"
          "alb.ingress.kubernetes.io/healthcheck-path" = "/api/health"
          "external-dns.alpha.kubernetes.io/hostname"  = local.grafana_host
        }
      }

      service = {
        type = "ClusterIP"
      }

      # Behind ALB → TLS terminates at ALB, in-cluster traffic is HTTP.
      "grafana.ini" = {
        server = {
          domain              = local.grafana_host
          root_url            = "https://${local.grafana_host}"
          serve_from_sub_path = false
        }
      }
    }
  })]

  depends_on = [kubectl_manifest.vault_static_secret_grafana]
}

# ─── Loki (single-binary, filesystem backend on gp3 PVC) ──────────────────

resource "helm_release" "loki" {
  name       = "loki"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = var.loki_version
  wait       = true
  timeout    = 600

  values = [yamlencode({
    deploymentMode = "SingleBinary"

    loki = {
      auth_enabled = false
      commonConfig = {
        replication_factor = 1
      }
      storage = {
        type = "filesystem"
      }
      schemaConfig = {
        configs = [{
          from         = "2024-01-01"
          store        = "tsdb"
          object_store = "filesystem"
          schema       = "v13"
          index = {
            prefix = "loki_index_"
            period = "24h"
          }
        }]
      }
      # Single-binary wants a ring store; memberlist works in-pod.
      ingester = {
        chunk_encoding = "snappy"
      }
      limits_config = {
        retention_period          = "168h"
        allow_structured_metadata = true
        volume_enabled            = true
      }
    }

    singleBinary = {
      replicas = 1
      persistence = {
        enabled      = true
        storageClass = var.storage_class
        size         = var.loki_storage_size
      }
    }

    # Single-binary mode: disable all the distributed components
    # (the chart still installs no-op releases otherwise).
    read           = { replicas = 0 }
    write          = { replicas = 0 }
    backend        = { replicas = 0 }
    ingester       = { replicas = 0 }
    querier        = { replicas = 0 }
    queryFrontend  = { replicas = 0 }
    queryScheduler = { replicas = 0 }
    distributor    = { replicas = 0 }
    compactor      = { replicas = 0 }
    indexGateway   = { replicas = 0 }
    bloomCompactor = { replicas = 0 }
    bloomGateway   = { replicas = 0 }

    # Keep the chart-managed Gateway (nginx) as the single entry point.
    gateway = {
      enabled = true
    }

    # Disable test pods — they block on wait=true and add no value.
    test       = { enabled = false }
    lokiCanary = { enabled = false }

    # MinIO is on by default (for S3 backend); we use filesystem, so disable.
    minio = { enabled = false }

    chunksCache  = { enabled = false }
    resultsCache = { enabled = false }
  })]

  depends_on = [kubernetes_namespace.observability]
}

# ─── Promtail (node-level log shipper → Loki) ─────────────────────────────

resource "helm_release" "promtail" {
  name       = "promtail"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = var.promtail_version
  wait       = true
  timeout    = 300

  values = [yamlencode({
    config = {
      clients = [{
        url = "http://loki-gateway.${kubernetes_namespace.observability.metadata[0].name}.svc.cluster.local/loki/api/v1/push"
      }]
    }
  })]

  depends_on = [helm_release.loki]
}

# ─── Vault ServiceMonitor ─────────────────────────────────────────────────
# Vault exposes Prometheus metrics at /v1/sys/metrics?format=prometheus.
# Unauthenticated access is enabled in the listener config (see
# vault-server/main.tf) so no token is required for scrape.

resource "kubectl_manifest" "vault_servicemonitor" {
  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "vault"
      namespace = kubernetes_namespace.observability.metadata[0].name
      labels = {
        release = "kps"
      }
    }
    spec = {
      namespaceSelector = {
        matchNames = [var.vault_namespace]
      }
      selector = {
        matchLabels = {
          "app.kubernetes.io/name"     = "vault"
          "app.kubernetes.io/instance" = "vault"
          component                    = "server"
        }
      }
      endpoints = [{
        port     = "https"
        scheme   = "https"
        path     = "/v1/sys/metrics"
        params   = { format = ["prometheus"] }
        interval = "30s"
        tlsConfig = {
          insecureSkipVerify = true
        }
        relabelings = [{
          sourceLabels = ["__meta_kubernetes_pod_name"]
          targetLabel  = "pod"
        }]
      }]
    }
  })

  depends_on = [helm_release.kube_prometheus_stack]
}

# ─── Shop services PodMonitor ────────────────────────────────────────────
# Selects the 5 Go services (web, auth, catalog, orders, gateway) in the
# consul namespace — all expose /metrics on port 8080 (same port as app traffic).

resource "kubectl_manifest" "shop_podmonitor" {
  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "shop-services"
      namespace = kubernetes_namespace.observability.metadata[0].name
      labels = {
        release = "kps"
      }
    }
    spec = {
      namespaceSelector = {
        matchNames = [var.apps_namespace]
      }
      selector = {
        matchExpressions = [{
          key      = "app"
          operator = "In"
          values   = ["web", "auth", "catalog", "orders", "gateway"]
        }]
      }
      podMetricsEndpoints = [{
        port       = ""
        targetPort = 8080
        path       = "/metrics"
        interval   = "30s"
        relabelings = [
          {
            sourceLabels = ["__meta_kubernetes_pod_label_app"]
            targetLabel  = "app"
          },
          {
            sourceLabels = ["__meta_kubernetes_namespace"]
            targetLabel  = "namespace"
          },
        ]
      }]
    }
  })

  depends_on = [helm_release.kube_prometheus_stack]
}

# ─── Envoy sidecar PodMonitor ────────────────────────────────────────────
# Consul's proxy-defaults enables envoy_prometheus_bind_addr=0.0.0.0:20200;
# sidecars inject alongside app containers in the consul namespace.

resource "kubectl_manifest" "envoy_podmonitor" {
  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "consul-envoy"
      namespace = kubernetes_namespace.observability.metadata[0].name
      labels = {
        release = "kps"
      }
    }
    spec = {
      namespaceSelector = {
        matchNames = [var.apps_namespace]
      }
      selector = {
        matchExpressions = [{
          key      = "consul.hashicorp.com/connect-inject-status"
          operator = "Exists"
        }]
      }
      podMetricsEndpoints = [{
        targetPort = 20200
        path       = "/metrics"
        interval   = "30s"
      }]
    }
  })

  depends_on = [helm_release.kube_prometheus_stack]
}

# ─── Netlix shop services dashboard (custom) ──────────────────────────────
# Minimal dashboard — RPS, p95 latency, 5xx rate — using the http_* metrics
# emitted by the promhttp middleware in each Go service. Loaded via the
# Grafana sidecar (label grafana_dashboard=1).

resource "kubernetes_config_map" "netlix_shop_dashboard" {
  metadata {
    name      = "netlix-shop-dashboard"
    namespace = kubernetes_namespace.observability.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "netlix-shop.json" = jsonencode({
      title         = "Netlix Shop Services"
      uid           = "netlix-shop"
      schemaVersion = 38
      timezone      = "browser"
      time          = { from = "now-1h", to = "now" }
      refresh       = "30s"
      tags          = ["netlix", "shop"]
      templating = {
        list = [{
          name       = "app"
          type       = "query"
          datasource = { type = "prometheus", uid = "prometheus" }
          query      = "label_values(http_requests_total{namespace=\"${var.apps_namespace}\"}, app)"
          refresh    = 2
          includeAll = true
          multi      = true
        }]
      }
      panels = [
        {
          id      = 1
          type    = "timeseries"
          title   = "Requests per second by service"
          gridPos = { x = 0, y = 0, w = 12, h = 8 }
          targets = [{
            expr         = "sum by (app) (rate(http_requests_total{namespace=\"${var.apps_namespace}\", app=~\"$app\"}[1m]))"
            legendFormat = "{{app}}"
            refId        = "A"
          }]
        },
        {
          id      = 2
          type    = "timeseries"
          title   = "p95 request latency by service"
          gridPos = { x = 12, y = 0, w = 12, h = 8 }
          targets = [{
            expr         = "histogram_quantile(0.95, sum by (app, le) (rate(http_request_duration_seconds_bucket{namespace=\"${var.apps_namespace}\", app=~\"$app\"}[5m])))"
            legendFormat = "{{app}}"
            refId        = "A"
          }]
          fieldConfig = {
            defaults = { unit = "s" }
          }
        },
        {
          id      = 3
          type    = "timeseries"
          title   = "5xx error rate by service"
          gridPos = { x = 0, y = 8, w = 12, h = 8 }
          targets = [{
            expr         = "sum by (app) (rate(http_requests_total{namespace=\"${var.apps_namespace}\", app=~\"$app\", status=~\"5..\"}[1m]))"
            legendFormat = "{{app}}"
            refId        = "A"
          }]
        },
        {
          id         = 4
          type       = "logs"
          title      = "Shop service logs"
          gridPos    = { x = 12, y = 8, w = 12, h = 8 }
          datasource = { type = "loki", uid = "loki" }
          targets = [{
            expr  = "{namespace=\"${var.apps_namespace}\"} |~ \".+\""
            refId = "A"
          }]
          options = { showTime = true, wrapLogMessage = true }
        },
      ]
    })
  }

  depends_on = [helm_release.kube_prometheus_stack]
}
