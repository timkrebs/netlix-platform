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

# ─── VSO identity for the observability namespace ────────────────────────
# VSO 0.9.0 resolves VaultAuth.spec.kubernetes.serviceAccount in the
# VaultStaticSecret's own namespace (not the VaultAuth's). Without an SA
# + local VaultAuth here, VSO fails with "ServiceAccount
# 'vault-secrets-operator' not found" and never syncs the Grafana admin
# Secret. Mirrors the pattern the shop services use in the `consul`
# namespace (app/manifests/base/vault-{auth,sa}.yaml).

resource "kubernetes_service_account" "vso_impersonator" {
  metadata {
    name      = "vault-secrets-operator-controller-manager"
    namespace = kubernetes_namespace.observability.metadata[0].name
  }
}

resource "kubectl_manifest" "vault_auth_observability" {
  yaml_body = yamlencode({
    apiVersion = "secrets.hashicorp.com/v1beta1"
    kind       = "VaultAuth"
    metadata = {
      name      = "default"
      namespace = kubernetes_namespace.observability.metadata[0].name
    }
    spec = {
      method             = "kubernetes"
      mount              = "kubernetes"
      namespace          = var.environment
      vaultConnectionRef = "vault-secrets-operator-system/default"
      kubernetes = {
        role                   = "netlix-vso"
        serviceAccount         = kubernetes_service_account.vso_impersonator.metadata[0].name
        tokenExpirationSeconds = 600
        # "vault" audience matches the Vault role's audience check;
        # "https://kubernetes.default.svc" is EKS's API-server default
        # audience, required because Vault calls TokenReview without an
        # explicit audience and K8s validates against its default.
        audiences = ["vault", "https://kubernetes.default.svc"]
      }
    }
  })

  depends_on = [kubernetes_service_account.vso_impersonator]
}

# ─── Grafana admin credentials synced from Vault via VSO ──────────────────
# Reads `secret/netlix/grafana` in the `dev` Vault namespace via the
# local VaultAuth above. The `netlix-vso` Vault policy grants read on
# `secret/data/netlix/*`, which covers this path.

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
      vaultAuthRef = "default"
      destination = {
        name   = local.grafana_admin_secret
        create = true
      }
    }
  })

  depends_on = [kubectl_manifest.vault_auth_observability]
}

# Give VSO time to reconcile the VaultStaticSecret and materialize the
# `grafana-admin` K8s Secret before Grafana's pod tries to mount it.
# Without this, the Grafana pod sits in ContainerCreating waiting on the
# secret — which blocks the helm release's wait and can exhaust its
# timeout on a cold cluster.
resource "time_sleep" "wait_for_grafana_secret" {
  depends_on      = [kubectl_manifest.vault_static_secret_grafana]
  create_duration = "90s"
}

# ─── kube-prometheus-stack (Prometheus + Grafana + AlertManager) ──────────

resource "helm_release" "kube_prometheus_stack" {
  name       = "kps"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.kube_prometheus_stack_version
  wait       = true
  # 30 min — cold-cluster first install pulls ~10 images (prometheus,
  # alertmanager, grafana + sidecars, operator, kube-state-metrics,
  # node-exporter), provisions 3 PVCs, and waits for Grafana to mount
  # the VSO-synced admin secret. 15 min was too tight.
  timeout = 1800
  atomic  = false

  values = [yamlencode({
    # Pick up ServiceMonitors / PodMonitors / Rules from any namespace
    # (shop services + Envoy in `consul`). Vault runs in a separate EKS
    # cluster, so it's scraped externally via the ALB (see
    # additionalScrapeConfigs below).
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

        # Cross-cluster scrape of Vault via the public ALB. Vault's
        # telemetry stanza + `unauthenticated_metrics_access = true` on
        # the listener (see vault-server/main.tf) let us hit
        # /v1/sys/metrics without a token. ACM cert is publicly trusted
        # so no insecure_skip_verify needed. Job name is deliberately
        # "vault" — the Grafana.com HashiCorp Vault dashboard (gnetId
        # 12904) hardcodes `job="vault"` in every panel query and
        # template variable, so renaming this job would leave the
        # dashboard blank.
        additionalScrapeConfigs = [{
          job_name        = "vault"
          scheme          = "https"
          metrics_path    = "/v1/sys/metrics"
          params          = { format = ["prometheus"] }
          scrape_interval = "30s"
          scrape_timeout  = "10s"
          static_configs = [{
            targets = ["vault.${var.environment}.${var.domain}"]
            labels = {
              vault_cluster = "vault-${var.environment}"
            }
          }]
        }]
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
      # Uses basic auth — every loki-gateway path except "/" is now
      # auth-gated (so external Promtail clients on the vault cluster
      # can push). Grafana's queries hit the same gateway and need the
      # same credentials. Same username/password the chart configures
      # on the gateway side.
      additionalDataSources = [
        {
          name          = "Loki"
          type          = "loki"
          url           = "http://loki-gateway.${kubernetes_namespace.observability.metadata[0].name}.svc.cluster.local"
          access        = "proxy"
          isDefault     = false
          basicAuth     = true
          basicAuthUser = var.loki_ingest_username
          secureJsonData = {
            basicAuthPassword = var.loki_ingest_password
          }
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

  depends_on = [
    kubectl_manifest.vault_static_secret_grafana,
    time_sleep.wait_for_grafana_secret,
  ]
}

# ─── Loki (single-binary, filesystem backend on gp3 PVC) ──────────────────
# Basic auth on the gateway is configured directly via the chart's
# gateway.basicAuth.username/password values (see helm release below).
# The chart renders these into a chart-managed Secret with a `.htpasswd`
# key in bcrypt format — which is what nginx's auth_basic_user_file
# directive actually expects. (We previously tried managing this Secret
# ourselves with separate `username`/`password` keys; nginx loads the
# secret as a flat htpasswd file at /etc/nginx/secrets/.htpasswd, found
# no valid entries, and 403'd every request.)
#
# Password is generated in vault-cluster workspace and read here via a
# tfe_outputs lookup (see workspaces/app-cluster/data.tf).

resource "helm_release" "loki" {
  name       = "loki"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = var.loki_version
  wait       = true
  # Single-binary Loki needs image pull + PVC bind + Gateway nginx pod;
  # 10 min is a safer cold-install budget than 10.
  timeout = 900
  atomic  = false

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
        retention_period          = var.loki_retention_period
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
    # Basic auth protects the public ingest endpoint that vault-cluster's
    # Promtail uses to ship audit logs cross-cluster. In-cluster query
    # traffic (Grafana → loki-gateway via service DNS) is also challenged
    # by basic auth — Grafana's datasource will be configured with the
    # same credentials.
    gateway = {
      enabled = true
      basicAuth = {
        enabled = true
        # Chart renders username/password into a managed Secret at
        # `<release>-loki-gateway` with a `.htpasswd` key (bcrypt-hashed),
        # mounted by nginx at /etc/nginx/secrets/.htpasswd.
        username = var.loki_ingest_username
        password = var.loki_ingest_password
      }
      ingress = {
        enabled          = true
        ingressClassName = "alb"
        hosts = [{
          host = "loki-ingest.${var.environment}.${var.domain}"
          paths = [{
            path     = "/"
            pathType = "Prefix"
          }]
        }]
        annotations = {
          "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
          "alb.ingress.kubernetes.io/target-type"      = "ip"
          "alb.ingress.kubernetes.io/certificate-arn"  = var.certificate_arn
          "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTPS\":443},{\"HTTP\":80}]"
          "alb.ingress.kubernetes.io/ssl-redirect"     = "443"
          "alb.ingress.kubernetes.io/backend-protocol" = "HTTP"
          # The chart's nginx ONLY serves "/" without basic auth (returns
          # "OK" 200). Every other path requires auth — including /ready.
          # Pointing the ALB healthcheck at "/" keeps targets healthy.
          "alb.ingress.kubernetes.io/healthcheck-path" = "/"
          "external-dns.alpha.kubernetes.io/hostname"  = "loki-ingest.${var.environment}.${var.domain}"
        }
      }
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

# Vault metrics are scraped cross-cluster via the public ALB using
# prometheus.prometheusSpec.additionalScrapeConfigs above — Vault runs
# in a separate EKS cluster (vault-cluster workspace), so in-cluster
# ServiceMonitor discovery from app-cluster's Prometheus can't reach it.

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

# ─── Vault audit log dashboard ────────────────────────────────────────────
# Loki LogQL queries built around the labels Promtail extracts from Vault's
# audit JSON (see components/vault-server/promtail.tf pipeline_stages):
#
#   audit_type    request | response
#   mount_type    kv | kubernetes | pki | system | identity | ...
#   operation     read | update | list | delete | create
#
#   Plus structured fields available after `| json` in LogQL queries:
#     auth_display_name              (from auth.display_name)
#     request_path                   (from request.path)
#     request_namespace_path         (from request.namespace.path)
#     response_error                 (from response.error)
#   LogQL's `| json` parser flattens nested JSON with underscores.
#   (Errors are filtered with `| json | response_error != ""` at query time.)
#
# Dashboard auto-loaded by Grafana sidecar via the grafana_dashboard=1 label.

resource "kubernetes_config_map" "vault_audit_dashboard" {
  metadata {
    name      = "netlix-vault-audit-dashboard"
    namespace = kubernetes_namespace.observability.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "vault-audit.json" = jsonencode({
      title         = "Vault Audit"
      uid           = "vault-audit"
      schemaVersion = 38
      timezone      = "browser"
      time          = { from = "now-1h", to = "now" }
      refresh       = "30s"
      tags          = ["netlix", "vault", "audit", "security"]
      templating = {
        list = [
          {
            name       = "mount_type"
            label      = "Mount type"
            type       = "query"
            datasource = { type = "loki", uid = "loki" }
            query = {
              label = "mount_type"
              type  = 1
            }
            refresh    = 2
            includeAll = true
            multi      = true
          },
          {
            name       = "operation"
            label      = "Operation"
            type       = "query"
            datasource = { type = "loki", uid = "loki" }
            query = {
              label = "operation"
              type  = 1
            }
            refresh    = 2
            includeAll = true
            multi      = true
          },
        ]
      }
      panels = [
        # ── Row 1: top-line stats ──
        {
          id         = 1
          type       = "stat"
          title      = "Audit events / sec"
          gridPos    = { x = 0, y = 0, w = 6, h = 4 }
          datasource = { type = "loki", uid = "loki" }
          targets = [{
            expr  = "sum(rate({namespace=\"vault\", container=\"vault\", audit_type=~\"request|response\", mount_type=~\"$mount_type\", operation=~\"$operation\"}[1m]))"
            refId = "A"
          }]
          options = {
            colorMode     = "value"
            graphMode     = "area"
            reduceOptions = { calcs = ["lastNotNull"] }
          }
          fieldConfig = {
            defaults = { unit = "ops" }
          }
        },
        {
          id         = 2
          type       = "stat"
          title      = "Errors / sec"
          gridPos    = { x = 6, y = 0, w = 6, h = 4 }
          datasource = { type = "loki", uid = "loki" }
          targets = [{
            expr  = "sum(rate({namespace=\"vault\", container=\"vault\", audit_type=\"response\", mount_type=~\"$mount_type\", operation=~\"$operation\"} | json | __error__=\"\" | response_error != \"\" [1m]))"
            refId = "A"
          }]
          options = {
            colorMode     = "value"
            graphMode     = "area"
            reduceOptions = { calcs = ["lastNotNull"] }
          }
          fieldConfig = {
            defaults = {
              unit = "ops"
              thresholds = {
                mode = "absolute"
                steps = [
                  { color = "green", value = null },
                  { color = "red", value = 0.1 },
                ]
              }
            }
          }
        },
        {
          id         = 3
          type       = "stat"
          title      = "Distinct identities (1h)"
          gridPos    = { x = 12, y = 0, w = 6, h = 4 }
          datasource = { type = "loki", uid = "loki" }
          targets = [{
            expr  = "count(count by(auth_display_name) (count_over_time({namespace=\"vault\", container=\"vault\", audit_type=\"response\"} | json [1h])))"
            refId = "A"
          }]
          options = {
            colorMode     = "value"
            reduceOptions = { calcs = ["lastNotNull"] }
          }
        },
        {
          id         = 4
          type       = "stat"
          title      = "Distinct vault paths (1h)"
          gridPos    = { x = 18, y = 0, w = 6, h = 4 }
          datasource = { type = "loki", uid = "loki" }
          targets = [{
            expr  = "count(count by(request_path) (count_over_time({namespace=\"vault\", container=\"vault\", audit_type=\"response\"} | json [1h])))"
            refId = "A"
          }]
          options = {
            colorMode     = "value"
            reduceOptions = { calcs = ["lastNotNull"] }
          }
        },
        # ── Row 2: time series ──
        {
          id         = 5
          type       = "timeseries"
          title      = "Events per second by mount type"
          gridPos    = { x = 0, y = 4, w = 12, h = 8 }
          datasource = { type = "loki", uid = "loki" }
          targets = [{
            expr         = "sum by (mount_type) (rate({namespace=\"vault\", container=\"vault\", audit_type=\"response\", operation=~\"$operation\"}[1m]))"
            legendFormat = "{{mount_type}}"
            refId        = "A"
          }]
        },
        {
          id         = 6
          type       = "timeseries"
          title      = "Events per second by operation"
          gridPos    = { x = 12, y = 4, w = 12, h = 8 }
          datasource = { type = "loki", uid = "loki" }
          targets = [{
            expr         = "sum by (operation) (rate({namespace=\"vault\", container=\"vault\", audit_type=\"response\", mount_type=~\"$mount_type\"}[1m]))"
            legendFormat = "{{operation}}"
            refId        = "A"
          }]
        },
        # ── Row 3: top-N tables ──
        {
          id         = 7
          type       = "barchart"
          title      = "Top identities (last 1h)"
          gridPos    = { x = 0, y = 12, w = 12, h = 8 }
          datasource = { type = "loki", uid = "loki" }
          targets = [{
            expr         = "topk(10, sum by(auth_display_name) (count_over_time({namespace=\"vault\", container=\"vault\", audit_type=\"response\", mount_type=~\"$mount_type\", operation=~\"$operation\"} | json [1h])))"
            legendFormat = "{{auth_display_name}}"
            refId        = "A"
          }]
        },
        {
          id         = 8
          type       = "barchart"
          title      = "Top vault paths (last 1h)"
          gridPos    = { x = 12, y = 12, w = 12, h = 8 }
          datasource = { type = "loki", uid = "loki" }
          targets = [{
            expr         = "topk(10, sum by(request_path) (count_over_time({namespace=\"vault\", container=\"vault\", audit_type=\"response\", mount_type=~\"$mount_type\", operation=~\"$operation\"} | json [1h])))"
            legendFormat = "{{request_path}}"
            refId        = "A"
          }]
        },
        # ── Row 4: live tail ──
        {
          id         = 9
          type       = "logs"
          title      = "Live audit tail"
          gridPos    = { x = 0, y = 20, w = 24, h = 12 }
          datasource = { type = "loki", uid = "loki" }
          targets = [{
            expr  = "{namespace=\"vault\", container=\"vault\", audit_type=\"response\", mount_type=~\"$mount_type\", operation=~\"$operation\"} | json | line_format \"{{.operation}} {{.request_path}} ({{.auth_display_name}})\""
            refId = "A"
          }]
          options = {
            showTime       = true
            wrapLogMessage = true
            sortOrder      = "Descending"
            dedupStrategy  = "none"
          }
        },
      ]
    })
  }

  depends_on = [helm_release.kube_prometheus_stack]
}
