resource "grafana_folder" "netlix" {
  title = "Netlix ${title(var.environment)}"
}

# ─── Dashboard 1: Cluster Overview ───────────────────────────────────────

resource "grafana_dashboard" "cluster_overview" {
  folder = grafana_folder.netlix.uid

  config_json = jsonencode({
    title       = "Cluster Overview — ${var.cluster_name}"
    uid         = "netlix-cluster-${var.environment}"
    tags        = ["netlix", var.environment, "cluster"]
    timezone    = "browser"
    refresh     = "30s"
    time        = { from = "now-1h", to = "now" }
    templating  = { list = [] }
    annotations = { list = [] }

    panels = [
      # ── Row: Node Health ──────────────────────────────────────────────
      {
        type      = "row"
        title     = "Node Health"
        gridPos   = { h = 1, w = 24, x = 0, y = 0 }
        collapsed = false
      },
      {
        type       = "stat"
        title      = "Nodes"
        gridPos    = { h = 4, w = 4, x = 0, y = 1 }
        datasource = { type = "prometheus", uid = var.prometheus_datasource_uid }
        targets = [{
          expr         = "count(up{job=\"kubelet\",cluster=\"${var.cluster_name}\"})"
          legendFormat = "Nodes"
        }]
        fieldConfig = {
          defaults = { thresholds = { steps = [
            { color = "green", value = null },
            { color = "red", value = 0 }
          ] } }
        }
      },
      {
        type       = "stat"
        title      = "Running Pods"
        gridPos    = { h = 4, w = 4, x = 4, y = 1 }
        datasource = { type = "prometheus", uid = var.prometheus_datasource_uid }
        targets = [{
          expr         = "sum(kubelet_running_pods{cluster=\"${var.cluster_name}\"})"
          legendFormat = "Pods"
        }]
        fieldConfig = {
          defaults = { thresholds = { steps = [
            { color = "green", value = null }
          ] } }
        }
      },
      {
        type       = "stat"
        title      = "Running Containers"
        gridPos    = { h = 4, w = 4, x = 8, y = 1 }
        datasource = { type = "prometheus", uid = var.prometheus_datasource_uid }
        targets = [{
          expr         = "sum(kubelet_running_containers{container_state=\"running\",cluster=\"${var.cluster_name}\"})"
          legendFormat = "Containers"
        }]
        fieldConfig = {
          defaults = { thresholds = { steps = [
            { color = "green", value = null }
          ] } }
        }
      },
      {
        type       = "gauge"
        title      = "Cluster CPU Usage"
        gridPos    = { h = 4, w = 6, x = 12, y = 1 }
        datasource = { type = "prometheus", uid = var.prometheus_datasource_uid }
        targets = [{
          expr         = "avg(rate(container_cpu_usage_seconds_total{cluster=\"${var.cluster_name}\",container!=\"\",container!=\"POD\"}[5m])) / avg(machine_cpu_cores{cluster=\"${var.cluster_name}\"}) * 100"
          legendFormat = "CPU %"
        }]
        fieldConfig = {
          defaults = {
            unit = "percent"
            min  = 0
            max  = 100
            thresholds = { steps = [
              { color = "green", value = null },
              { color = "yellow", value = 60 },
              { color = "red", value = 80 }
            ] }
          }
        }
      },
      {
        type       = "gauge"
        title      = "Cluster Memory Usage"
        gridPos    = { h = 4, w = 6, x = 18, y = 1 }
        datasource = { type = "prometheus", uid = var.prometheus_datasource_uid }
        targets = [{
          expr         = "sum(container_memory_working_set_bytes{cluster=\"${var.cluster_name}\",container!=\"\",container!=\"POD\"}) / sum(machine_memory_bytes{cluster=\"${var.cluster_name}\"}) * 100"
          legendFormat = "Memory %"
        }]
        fieldConfig = {
          defaults = {
            unit = "percent"
            min  = 0
            max  = 100
            thresholds = { steps = [
              { color = "green", value = null },
              { color = "yellow", value = 60 },
              { color = "red", value = 80 }
            ] }
          }
        }
      },

      # ── Row: Resource Usage Over Time ─────────────────────────────────
      {
        type      = "row"
        title     = "Resource Usage Over Time"
        gridPos   = { h = 1, w = 24, x = 0, y = 5 }
        collapsed = false
      },
      {
        type       = "timeseries"
        title      = "CPU Usage by Namespace"
        gridPos    = { h = 8, w = 12, x = 0, y = 6 }
        datasource = { type = "prometheus", uid = var.prometheus_datasource_uid }
        targets = [{
          expr         = "sum(rate(container_cpu_usage_seconds_total{cluster=\"${var.cluster_name}\",container!=\"\",container!=\"POD\"}[5m])) by (namespace)"
          legendFormat = "{{ namespace }}"
        }]
        fieldConfig = {
          defaults = {
            unit   = "cores"
            custom = { fillOpacity = 20, stacking = { mode = "normal" } }
          }
        }
      },
      {
        type       = "timeseries"
        title      = "Memory Usage by Namespace"
        gridPos    = { h = 8, w = 12, x = 12, y = 6 }
        datasource = { type = "prometheus", uid = var.prometheus_datasource_uid }
        targets = [{
          expr         = "sum(container_memory_working_set_bytes{cluster=\"${var.cluster_name}\",container!=\"\",container!=\"POD\"}) by (namespace)"
          legendFormat = "{{ namespace }}"
        }]
        fieldConfig = {
          defaults = {
            unit   = "bytes"
            custom = { fillOpacity = 20, stacking = { mode = "normal" } }
          }
        }
      },

      # ── Row: Pod Resource Usage (consul namespace) ────────────────────
      {
        type      = "row"
        title     = "Pod Resources — consul namespace"
        gridPos   = { h = 1, w = 24, x = 0, y = 14 }
        collapsed = false
      },
      {
        type       = "timeseries"
        title      = "Pod CPU Usage"
        gridPos    = { h = 8, w = 12, x = 0, y = 15 }
        datasource = { type = "prometheus", uid = var.prometheus_datasource_uid }
        targets = [{
          expr         = "sum(rate(container_cpu_usage_seconds_total{cluster=\"${var.cluster_name}\",namespace=\"consul\",container!=\"\",container!=\"POD\"}[5m])) by (pod)"
          legendFormat = "{{ pod }}"
        }]
        fieldConfig = { defaults = { unit = "cores" } }
      },
      {
        type       = "timeseries"
        title      = "Pod Memory Usage"
        gridPos    = { h = 8, w = 12, x = 12, y = 15 }
        datasource = { type = "prometheus", uid = var.prometheus_datasource_uid }
        targets = [{
          expr         = "sum(container_memory_working_set_bytes{cluster=\"${var.cluster_name}\",namespace=\"consul\",container!=\"\",container!=\"POD\"}) by (pod)"
          legendFormat = "{{ pod }}"
        }]
        fieldConfig = { defaults = { unit = "bytes" } }
      },

      # ── Row: Network ──────────────────────────────────────────────────
      {
        type      = "row"
        title     = "Network I/O"
        gridPos   = { h = 1, w = 24, x = 0, y = 23 }
        collapsed = false
      },
      {
        type       = "timeseries"
        title      = "Network Receive (consul)"
        gridPos    = { h = 8, w = 12, x = 0, y = 24 }
        datasource = { type = "prometheus", uid = var.prometheus_datasource_uid }
        targets = [{
          expr         = "sum(rate(container_network_receive_bytes_total{cluster=\"${var.cluster_name}\",namespace=\"consul\"}[5m])) by (pod)"
          legendFormat = "{{ pod }}"
        }]
        fieldConfig = { defaults = { unit = "Bps" } }
      },
      {
        type       = "timeseries"
        title      = "Network Transmit (consul)"
        gridPos    = { h = 8, w = 12, x = 12, y = 24 }
        datasource = { type = "prometheus", uid = var.prometheus_datasource_uid }
        targets = [{
          expr         = "sum(rate(container_network_transmit_bytes_total{cluster=\"${var.cluster_name}\",namespace=\"consul\"}[5m])) by (pod)"
          legendFormat = "{{ pod }}"
        }]
        fieldConfig = { defaults = { unit = "Bps" } }
      }
    ]

    schemaVersion = 39
  })
}

# ─── Dashboard 2: Application Services ──────────────────────────────────

resource "grafana_dashboard" "application_services" {
  folder = grafana_folder.netlix.uid

  config_json = jsonencode({
    title       = "Application Services — ${var.environment}"
    uid         = "netlix-app-${var.environment}"
    tags        = ["netlix", var.environment, "application"]
    timezone    = "browser"
    refresh     = "30s"
    time        = { from = "now-1h", to = "now" }
    templating  = { list = [] }
    annotations = { list = [] }

    panels = [
      # ── Row: Request Overview ─────────────────────────────────────────
      {
        type      = "row"
        title     = "Request Overview"
        gridPos   = { h = 1, w = 24, x = 0, y = 0 }
        collapsed = false
      },
      {
        type       = "stat"
        title      = "Total Request Rate"
        gridPos    = { h = 4, w = 6, x = 0, y = 1 }
        datasource = { type = "prometheus", uid = var.prometheus_datasource_uid }
        targets = [{
          expr         = "sum(rate(envoy_http_downstream_rq_total{cluster=\"${var.cluster_name}\",namespace=\"consul\"}[5m]))"
          legendFormat = "req/s"
        }]
        fieldConfig = {
          defaults = {
            unit       = "reqps"
            thresholds = { steps = [{ color = "green", value = null }] }
          }
        }
      },
      {
        type       = "stat"
        title      = "5xx Error Rate"
        gridPos    = { h = 4, w = 6, x = 6, y = 1 }
        datasource = { type = "prometheus", uid = var.prometheus_datasource_uid }
        targets = [{
          expr         = "sum(rate(envoy_http_downstream_rq_xx{cluster=\"${var.cluster_name}\",namespace=\"consul\",envoy_response_code_class=\"5\"}[5m]))"
          legendFormat = "5xx/s"
        }]
        fieldConfig = {
          defaults = {
            unit = "reqps"
            thresholds = { steps = [
              { color = "green", value = null },
              { color = "yellow", value = 0.01 },
              { color = "red", value = 0.1 }
            ] }
          }
        }
      },
      {
        type       = "stat"
        title      = "Active Connections"
        gridPos    = { h = 4, w = 6, x = 12, y = 1 }
        datasource = { type = "prometheus", uid = var.prometheus_datasource_uid }
        targets = [{
          expr         = "sum(envoy_http_downstream_cx_active{cluster=\"${var.cluster_name}\",namespace=\"consul\"})"
          legendFormat = "connections"
        }]
        fieldConfig = {
          defaults = { thresholds = { steps = [{ color = "blue", value = null }] } }
        }
      },
      {
        type       = "stat"
        title      = "Error Ratio"
        gridPos    = { h = 4, w = 6, x = 18, y = 1 }
        datasource = { type = "prometheus", uid = var.prometheus_datasource_uid }
        targets = [{
          expr         = "sum(rate(envoy_http_downstream_rq_xx{cluster=\"${var.cluster_name}\",namespace=\"consul\",envoy_response_code_class=\"5\"}[5m])) / sum(rate(envoy_http_downstream_rq_total{cluster=\"${var.cluster_name}\",namespace=\"consul\"}[5m])) * 100"
          legendFormat = "error %"
        }]
        fieldConfig = {
          defaults = {
            unit = "percent"
            thresholds = { steps = [
              { color = "green", value = null },
              { color = "yellow", value = 1 },
              { color = "red", value = 5 }
            ] }
          }
        }
      },

      # ── Row: Request Rate by Service ──────────────────────────────────
      {
        type      = "row"
        title     = "Traffic by Service"
        gridPos   = { h = 1, w = 24, x = 0, y = 5 }
        collapsed = false
      },
      {
        type       = "timeseries"
        title      = "Request Rate by Pod"
        gridPos    = { h = 8, w = 12, x = 0, y = 6 }
        datasource = { type = "prometheus", uid = var.prometheus_datasource_uid }
        targets = [{
          expr         = "sum(rate(envoy_http_downstream_rq_total{cluster=\"${var.cluster_name}\",namespace=\"consul\"}[5m])) by (pod)"
          legendFormat = "{{ pod }}"
        }]
        fieldConfig = { defaults = { unit = "reqps", custom = { fillOpacity = 10 } } }
      },
      {
        type       = "timeseries"
        title      = "Response Status Codes"
        gridPos    = { h = 8, w = 12, x = 12, y = 6 }
        datasource = { type = "prometheus", uid = var.prometheus_datasource_uid }
        targets = [
          {
            expr         = "sum(rate(envoy_http_downstream_rq_xx{cluster=\"${var.cluster_name}\",namespace=\"consul\",envoy_response_code_class=\"2\"}[5m]))"
            legendFormat = "2xx"
          },
          {
            expr         = "sum(rate(envoy_http_downstream_rq_xx{cluster=\"${var.cluster_name}\",namespace=\"consul\",envoy_response_code_class=\"4\"}[5m]))"
            legendFormat = "4xx"
          },
          {
            expr         = "sum(rate(envoy_http_downstream_rq_xx{cluster=\"${var.cluster_name}\",namespace=\"consul\",envoy_response_code_class=\"5\"}[5m]))"
            legendFormat = "5xx"
          }
        ]
        fieldConfig = {
          defaults = { unit = "reqps", custom = { fillOpacity = 20 } }
          overrides = [
            { matcher = { id = "byName", options = "2xx" }, properties = [{ id = "color", value = { fixedColor = "green", mode = "fixed" } }] },
            { matcher = { id = "byName", options = "4xx" }, properties = [{ id = "color", value = { fixedColor = "yellow", mode = "fixed" } }] },
            { matcher = { id = "byName", options = "5xx" }, properties = [{ id = "color", value = { fixedColor = "red", mode = "fixed" } }] }
          ]
        }
      },

      # ── Row: Latency ──────────────────────────────────────────────────
      {
        type      = "row"
        title     = "Latency"
        gridPos   = { h = 1, w = 24, x = 0, y = 14 }
        collapsed = false
      },
      {
        type       = "timeseries"
        title      = "Request Duration (p50 / p95 / p99)"
        gridPos    = { h = 8, w = 24, x = 0, y = 15 }
        datasource = { type = "prometheus", uid = var.prometheus_datasource_uid }
        targets = [
          {
            expr         = "histogram_quantile(0.50, sum(rate(envoy_http_downstream_rq_time_bucket{cluster=\"${var.cluster_name}\",namespace=\"consul\"}[5m])) by (le))"
            legendFormat = "p50"
          },
          {
            expr         = "histogram_quantile(0.95, sum(rate(envoy_http_downstream_rq_time_bucket{cluster=\"${var.cluster_name}\",namespace=\"consul\"}[5m])) by (le))"
            legendFormat = "p95"
          },
          {
            expr         = "histogram_quantile(0.99, sum(rate(envoy_http_downstream_rq_time_bucket{cluster=\"${var.cluster_name}\",namespace=\"consul\"}[5m])) by (le))"
            legendFormat = "p99"
          }
        ]
        fieldConfig = {
          defaults = { unit = "ms", custom = { fillOpacity = 5 } }
          overrides = [
            { matcher = { id = "byName", options = "p50" }, properties = [{ id = "color", value = { fixedColor = "green", mode = "fixed" } }] },
            { matcher = { id = "byName", options = "p95" }, properties = [{ id = "color", value = { fixedColor = "orange", mode = "fixed" } }] },
            { matcher = { id = "byName", options = "p99" }, properties = [{ id = "color", value = { fixedColor = "red", mode = "fixed" } }] }
          ]
        }
      },

      # ── Row: Service Resources ────────────────────────────────────────
      {
        type      = "row"
        title     = "Service Resources"
        gridPos   = { h = 1, w = 24, x = 0, y = 23 }
        collapsed = false
      },
      {
        type       = "timeseries"
        title      = "CPU Usage — web vs api"
        gridPos    = { h = 8, w = 12, x = 0, y = 24 }
        datasource = { type = "prometheus", uid = var.prometheus_datasource_uid }
        targets = [
          {
            expr         = "sum(rate(container_cpu_usage_seconds_total{cluster=\"${var.cluster_name}\",namespace=\"consul\",pod=~\"web.*\",container!=\"POD\",container!=\"\"}[5m]))"
            legendFormat = "web"
          },
          {
            expr         = "sum(rate(container_cpu_usage_seconds_total{cluster=\"${var.cluster_name}\",namespace=\"consul\",pod=~\"api.*\",container!=\"POD\",container!=\"\"}[5m]))"
            legendFormat = "api"
          }
        ]
        fieldConfig = { defaults = { unit = "cores", custom = { fillOpacity = 15 } } }
      },
      {
        type       = "timeseries"
        title      = "Memory Usage — web vs api"
        gridPos    = { h = 8, w = 12, x = 12, y = 24 }
        datasource = { type = "prometheus", uid = var.prometheus_datasource_uid }
        targets = [
          {
            expr         = "sum(container_memory_working_set_bytes{cluster=\"${var.cluster_name}\",namespace=\"consul\",pod=~\"web.*\",container!=\"POD\",container!=\"\"})"
            legendFormat = "web"
          },
          {
            expr         = "sum(container_memory_working_set_bytes{cluster=\"${var.cluster_name}\",namespace=\"consul\",pod=~\"api.*\",container!=\"POD\",container!=\"\"})"
            legendFormat = "api"
          }
        ]
        fieldConfig = { defaults = { unit = "bytes", custom = { fillOpacity = 15 } } }
      }
    ]

    schemaVersion = 39
  })
}

# ─── Dashboard 3: Logs ──────────────────────────────────────────────────

resource "grafana_dashboard" "logs" {
  folder = grafana_folder.netlix.uid

  config_json = jsonencode({
    title    = "Logs — ${var.environment}"
    uid      = "netlix-logs-${var.environment}"
    tags     = ["netlix", var.environment, "logs"]
    timezone = "browser"
    refresh  = "30s"
    time     = { from = "now-1h", to = "now" }
    templating = { list = [
      {
        name    = "namespace"
        type    = "custom"
        current = { text = "consul", value = "consul" }
        options = [
          { text = "consul", value = "consul", selected = true },
          { text = "argocd", value = "argocd" },
          { text = "grafana-system", value = "grafana-system" },
          { text = "vault-secrets-operator-system", value = "vault-secrets-operator-system" },
          { text = "kube-system", value = "kube-system" }
        ]
        query = "consul,argocd,grafana-system,vault-secrets-operator-system,kube-system"
      },
      {
        name    = "search"
        type    = "textbox"
        current = { text = "", value = "" }
        label   = "Search"
      }
    ] }
    annotations = { list = [] }

    panels = [
      # ── Row: Log Volume ───────────────────────────────────────────────
      {
        type      = "row"
        title     = "Log Volume"
        gridPos   = { h = 1, w = 24, x = 0, y = 0 }
        collapsed = false
      },
      {
        type       = "timeseries"
        title      = "Log Lines per Second"
        gridPos    = { h = 6, w = 24, x = 0, y = 1 }
        datasource = { type = "loki", uid = var.loki_datasource_uid }
        targets = [{
          expr         = "sum(rate({cluster=\"${var.cluster_name}\",namespace=\"$namespace\"}[5m])) by (app)"
          legendFormat = "{{ app }}"
        }]
        fieldConfig = {
          defaults = { unit = "short", custom = { fillOpacity = 30, stacking = { mode = "normal" } } }
        }
      },

      # ── Row: Error Logs ───────────────────────────────────────────────
      {
        type      = "row"
        title     = "Error Logs"
        gridPos   = { h = 1, w = 24, x = 0, y = 7 }
        collapsed = false
      },
      {
        type       = "timeseries"
        title      = "Error Log Rate"
        gridPos    = { h = 6, w = 24, x = 0, y = 8 }
        datasource = { type = "loki", uid = var.loki_datasource_uid }
        targets = [{
          expr         = "sum(rate({cluster=\"${var.cluster_name}\",namespace=\"$namespace\"} |~ \"(?i)(error|panic|fatal|exception)\"[5m])) by (app)"
          legendFormat = "{{ app }}"
        }]
        fieldConfig = {
          defaults = {
            unit   = "short"
            custom = { fillOpacity = 20 }
            color  = { mode = "fixed", fixedColor = "red" }
          }
        }
      },

      # ── Row: Live Log Stream ──────────────────────────────────────────
      {
        type      = "row"
        title     = "Log Stream"
        gridPos   = { h = 1, w = 24, x = 0, y = 14 }
        collapsed = false
      },
      {
        type       = "logs"
        title      = "Application Logs"
        gridPos    = { h = 16, w = 24, x = 0, y = 15 }
        datasource = { type = "loki", uid = var.loki_datasource_uid }
        targets = [{
          expr = "{cluster=\"${var.cluster_name}\",namespace=\"$namespace\"} $${search:pipe}"
        }]
        options = {
          showTime         = true
          showLabels       = true
          showCommonLabels = false
          wrapLogMessage   = true
          sortOrder        = "Descending"
          enableLogDetails = true
        }
      }
    ]

    schemaVersion = 39
  })
}
