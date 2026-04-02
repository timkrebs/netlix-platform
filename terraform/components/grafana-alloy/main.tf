resource "helm_release" "alloy" {
  name             = "alloy"
  namespace        = "grafana-system"
  create_namespace = true
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "alloy"
  version          = "0.12.0"

  values = [yamlencode({
    alloy = {
      configMap = {
        content = <<-ALLOY
          // ── Prometheus: discover and scrape annotated pods ────────────────────

          discovery.kubernetes "pods" {
            role = "pod"
          }

          discovery.relabel "pod_annotations" {
            targets = discovery.kubernetes.pods.targets

            rule {
              source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_scrape"]
              regex         = "true"
              action        = "keep"
            }
            rule {
              source_labels = ["__meta_kubernetes_pod_ip", "__meta_kubernetes_pod_annotation_prometheus_io_port"]
              separator     = ":"
              target_label  = "__address__"
              action        = "replace"
            }
            rule {
              source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_path"]
              target_label  = "__metrics_path__"
              action        = "replace"
            }
            rule {
              source_labels = ["__meta_kubernetes_namespace"]
              target_label  = "namespace"
              action        = "replace"
            }
            rule {
              source_labels = ["__meta_kubernetes_pod_name"]
              target_label  = "pod"
              action        = "replace"
            }
            rule {
              source_labels = ["__meta_kubernetes_pod_label_app"]
              target_label  = "app"
              action        = "replace"
            }
          }

          prometheus.scrape "pods" {
            targets    = discovery.relabel.pod_annotations.output
            forward_to = [prometheus.remote_write.grafana_cloud.receiver]

            scrape_interval = "30s"
          }

          // ── Prometheus: scrape kubelet and cAdvisor ───────────────────────────

          discovery.kubernetes "nodes" {
            role = "node"
          }

          prometheus.scrape "kubelet" {
            targets    = discovery.kubernetes.nodes.targets
            forward_to = [prometheus.remote_write.grafana_cloud.receiver]

            scheme = "https"
            tls_config {
              insecure_skip_verify = true
            }
            bearer_token_file = "/var/run/secrets/kubernetes.io/serviceaccount/token"

            scrape_interval = "30s"
          }

          discovery.relabel "cadvisor" {
            targets = discovery.kubernetes.nodes.targets

            rule {
              target_label = "__metrics_path__"
              replacement  = "/metrics/cadvisor"
              action       = "replace"
            }
          }

          prometheus.scrape "cadvisor" {
            targets    = discovery.relabel.cadvisor.output
            forward_to = [prometheus.remote_write.grafana_cloud.receiver]

            scheme = "https"
            tls_config {
              insecure_skip_verify = true
            }
            bearer_token_file = "/var/run/secrets/kubernetes.io/serviceaccount/token"

            scrape_interval = "30s"
          }

          // ── Prometheus: remote write to Grafana Cloud ────────────────────────

          prometheus.remote_write "grafana_cloud" {
            endpoint {
              url = env("GRAFANA_PROM_URL")

              basic_auth {
                username = env("GRAFANA_PROM_USERNAME")
                password = env("GRAFANA_API_KEY")
              }
            }

            external_labels = {
              cluster     = "${var.cluster_name}",
              environment = "${var.environment}",
            }
          }

          // ── Loki: collect container logs ──────────────────────────────────────

          discovery.kubernetes "pod_logs" {
            role = "pod"
          }

          discovery.relabel "pod_logs" {
            targets = discovery.kubernetes.pod_logs.targets

            rule {
              source_labels = ["__meta_kubernetes_namespace"]
              target_label  = "namespace"
              action        = "replace"
            }
            rule {
              source_labels = ["__meta_kubernetes_pod_name"]
              target_label  = "pod"
              action        = "replace"
            }
            rule {
              source_labels = ["__meta_kubernetes_pod_container_name"]
              target_label  = "container"
              action        = "replace"
            }
            rule {
              source_labels = ["__meta_kubernetes_pod_label_app"]
              target_label  = "app"
              action        = "replace"
            }
          }

          loki.source.kubernetes "pods" {
            targets    = discovery.relabel.pod_logs.output
            forward_to = [loki.write.grafana_cloud.receiver]
          }

          loki.write "grafana_cloud" {
            endpoint {
              url = env("GRAFANA_LOKI_URL")

              basic_auth {
                username = env("GRAFANA_LOKI_USERNAME")
                password = env("GRAFANA_API_KEY")
              }
            }

            external_labels = {
              cluster     = "${var.cluster_name}",
              environment = "${var.environment}",
            }
          }

          // ── Alerting rules ───────────────────────────────────────────────────

          prometheus.rules "kubernetes_alerts" {
            rule {
              alert = "PodCrashLooping"
              expr  = "increase(kube_pod_container_status_restarts_total[15m]) > 3"
              for   = "5m"
              labels = {
                severity = "warning",
              }
              annotations = {
                summary     = "Pod {{ "{{" }} $labels.namespace {{ "}}" }}/{{ "{{" }} $labels.pod {{ "}}" }} is crash looping",
                description = "Pod has restarted more than 3 times in the last 15 minutes.",
              }
            }

            rule {
              alert = "PodOOMKilled"
              expr  = "kube_pod_container_status_last_terminated_reason{reason=\"OOMKilled\"} == 1"
              for   = "0m"
              labels = {
                severity = "warning",
              }
              annotations = {
                summary     = "Pod {{ "{{" }} $labels.namespace {{ "}}" }}/{{ "{{" }} $labels.pod {{ "}}" }} was OOMKilled",
                description = "Container {{ "{{" }} $labels.container {{ "}}" }} was terminated due to OOM.",
              }
            }

            rule {
              alert = "PodNotReady"
              expr  = "kube_pod_status_ready{condition=\"true\"} == 0"
              for   = "5m"
              labels = {
                severity = "warning",
              }
              annotations = {
                summary     = "Pod {{ "{{" }} $labels.namespace {{ "}}" }}/{{ "{{" }} $labels.pod {{ "}}" }} is not ready",
                description = "Pod has been in a non-ready state for more than 5 minutes.",
              }
            }

            rule {
              alert = "HighErrorRate"
              expr  = "sum(rate(envoy_http_downstream_rq_xx{envoy_response_code_class=\"5\"}[5m])) by (namespace, pod) > 0.1"
              for   = "5m"
              labels = {
                severity = "critical",
              }
              annotations = {
                summary     = "High 5xx error rate on {{ "{{" }} $labels.pod {{ "}}" }}",
                description = "Pod {{ "{{" }} $labels.namespace {{ "}}" }}/{{ "{{" }} $labels.pod {{ "}}" }} has elevated 5xx error rate.",
              }
            }

            rule {
              alert = "NodeNotReady"
              expr  = "kube_node_status_condition{condition=\"Ready\",status=\"true\"} == 0"
              for   = "5m"
              labels = {
                severity = "critical",
              }
              annotations = {
                summary     = "Node {{ "{{" }} $labels.node {{ "}}" }} is not ready",
                description = "Node has been in a non-ready state for more than 5 minutes.",
              }
            }

            rule {
              alert = "PersistentVolumeAlmostFull"
              expr  = "kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes > 0.85"
              for   = "10m"
              labels = {
                severity = "warning",
              }
              annotations = {
                summary     = "PVC {{ "{{" }} $labels.persistentvolumeclaim {{ "}}" }} is over 85% full",
                description = "Persistent volume in {{ "{{" }} $labels.namespace {{ "}}" }} is running low on space.",
              }
            }

            rule {
              alert = "TLSCertExpiringSoon"
              expr  = "(certmanager_certificate_expiration_timestamp_seconds - time()) / 3600 < 24"
              for   = "10m"
              labels = {
                severity = "warning",
              }
              annotations = {
                summary     = "TLS certificate expiring within 24 hours",
                description = "Certificate {{ "{{" }} $labels.name {{ "}}" }} in {{ "{{" }} $labels.namespace {{ "}}" }} expires soon.",
              }
            }
          }
        ALLOY
      }

      extraEnv = [
        {
          name = "GRAFANA_PROM_URL"
          valueFrom = {
            secretKeyRef = {
              name = "alloy-grafana-credentials"
              key  = "GRAFANA_PROM_URL"
            }
          }
        },
        {
          name = "GRAFANA_PROM_USERNAME"
          valueFrom = {
            secretKeyRef = {
              name = "alloy-grafana-credentials"
              key  = "GRAFANA_PROM_USERNAME"
            }
          }
        },
        {
          name = "GRAFANA_LOKI_URL"
          valueFrom = {
            secretKeyRef = {
              name = "alloy-grafana-credentials"
              key  = "GRAFANA_LOKI_URL"
            }
          }
        },
        {
          name = "GRAFANA_LOKI_USERNAME"
          valueFrom = {
            secretKeyRef = {
              name = "alloy-grafana-credentials"
              key  = "GRAFANA_LOKI_USERNAME"
            }
          }
        },
        {
          name = "GRAFANA_API_KEY"
          valueFrom = {
            secretKeyRef = {
              name = "alloy-grafana-credentials"
              key  = "GRAFANA_API_KEY"
            }
          }
        },
      ]
    }

    serviceAccount = {
      create = true
    }

    rbac = {
      create = true
    }

    controller = {
      type = "daemonset"
    }
  })]
}
