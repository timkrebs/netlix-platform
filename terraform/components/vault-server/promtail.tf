# ─── Promtail: ship Vault audit logs to app-cluster's Loki ───────────────
#
# Vault audit device emits one JSON line per request/response to container
# stdout (configured in components/vault-config/audit.tf as type=file with
# file_path="stdout" — the magic value that makes Vault write to the
# container's stdout instead of a real file). Kubelet captures stdout under
# /var/log/containers, where this Promtail DaemonSet tails it.
#
# The pipeline:
#   1. CRI parser unwraps the kubelet log envelope.
#   2. Drop everything that's not JSON (Vault's startup/raft/info messages
#      are plain-text and would just be noise in the audit dashboard).
#   3. Parse audit JSON, extracting low-cardinality fields as labels and
#      higher-cardinality fields as structured metadata so LogQL queries
#      can `| json` and filter without label cardinality blowing up.
#   4. Drop entries that aren't audit (no `type` field set to request/response).
#
# Push target is the app-cluster's loki-gateway via the public ALB ingress
# (loki-ingest.<env>.<domain>) with HTTP basic auth. Password comes from a
# random_password in the vault-cluster workspace, also surfaced as an output
# the app-cluster reads back via tfe_outputs.

resource "kubernetes_secret" "loki_ingest_credentials" {
  metadata {
    name      = "loki-ingest-credentials"
    namespace = kubernetes_namespace.vault.metadata[0].name
  }
  data = {
    # Password is mounted as a file so Promtail's clients[].basic_auth
    # block can reference it via `password_file` — keeps the password out
    # of the pod's environment and out of `kubectl describe` output.
    password = var.loki_ingest_password
  }
  type = "Opaque"
}

resource "helm_release" "promtail" {
  name       = "promtail"
  namespace  = kubernetes_namespace.vault.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = var.promtail_chart_version
  # `wait = false` is intentional. Promtail is a DaemonSet on a small,
  # capacity-constrained cluster (t3.small caps at 11 pods/node) where
  # the rolling update can stall if the next replacement pod can't
  # immediately schedule. Waiting blocks the apply on a non-critical
  # log-shipper that has no synchronous downstream consumer — the
  # DaemonSet eventually converges (or surfaces capacity issues that
  # are addressed separately, e.g. via VPC CNI prefix delegation or a
  # node refresh). With `wait = true` the apply timed out at 5 min
  # because the third pod was Pending behind a maxUnavailable=1 stall.
  wait    = false
  timeout = 600

  values = [yamlencode({
    # Mount the credentials secret as a file at /etc/promtail-auth/password.
    extraVolumes = [{
      name = "loki-ingest-credentials"
      secret = {
        secretName = kubernetes_secret.loki_ingest_credentials.metadata[0].name
      }
    }]
    extraVolumeMounts = [{
      name      = "loki-ingest-credentials"
      mountPath = "/etc/promtail-auth"
      readOnly  = true
    }]

    config = {
      clients = [{
        url = "${var.loki_ingest_endpoint}/loki/api/v1/push"
        basic_auth = {
          username      = var.loki_ingest_username
          password_file = "/etc/promtail-auth/password"
        }
        # Tag every line shipped from this cluster so dashboards can
        # distinguish vault-cluster logs from app-cluster logs (when both
        # land in the same Loki).
        external_labels = {
          source_cluster = "${var.project}-vault-${var.environment}"
          environment    = var.environment
        }
        # Larger batch + longer wait reduce request count to the public
        # ALB. Vault audit is bursty (every API call) but rarely high-rate
        # in a demo cluster — buffering up to 5s of events is fine.
        batchwait = "5s"
        batchsize = 1048576
      }]

      # Only scrape the Vault container. Anything else (kube-system,
      # cert-manager, etc.) is captured by other observability tooling on
      # the app cluster and would add noise to the audit dashboard.
      snippets = {
        scrapeConfigs = <<-EOT
          - job_name: vault-audit
            kubernetes_sd_configs:
              - role: pod
            pipeline_stages:
              # 1. Strip the kubelet CRI log envelope ("<timestamp> stdout F <line>").
              - cri: {}

              # 2. Parse the audit JSON envelope into named expressions.
              #    Top-level `type` is "request" or "response"; presence of
              #    that field is what tells us this is actually audit.
              #    Non-JSON lines (Vault startup/raft messages) fail JSON
              #    parsing silently and the audit_type expression stays
              #    empty — they get dropped by the next stage.
              - json:
                  expressions:
                    audit_type: type
                    mount_type: '"request".mount_type'
                    vault_namespace_path: '"request".namespace.path'
                    operation: '"request".operation'
                    vault_path: '"request".path'
                    display_name: '"auth".display_name'
                    error: '"response".error'

              # 3. Drop anything that wasn't audit (no `type` set). This
              #    also handles non-JSON lines, since the JSON parse
              #    above leaves audit_type empty for them.
              - drop:
                  source: audit_type
                  expression: '^$'
                  drop_counter_reason: not_audit

              # 4. Promote only low-cardinality fields to labels — these
              #    are the dashboard's primary query dimensions.
              #
              #    audit_type      ~2 values (request, response)
              #    mount_type      ~10 values (kv, kubernetes, pki, system, identity, ...)
              #    operation       ~5 values (read, update, list, delete, create)
              #
              #    display_name, vault_path, vault_namespace_path, error
              #    stay as structured fields — they're either too
              #    high-cardinality or only relevant on subsets. LogQL
              #    queries `| json | display_name=~"..."` instead.
              #    For "has error" filtering at query time, use
              #    `| json | error != ""`.
              - labels:
                  audit_type:
                  mount_type:
                  operation:

            relabel_configs:
              # Discover only Vault server pods. The Vault statefulset's
              # pods all share label `app.kubernetes.io/name=vault`.
              - source_labels:
                  - __meta_kubernetes_namespace
                action: keep
                regex: vault
              - source_labels:
                  - __meta_kubernetes_pod_label_app_kubernetes_io_name
                action: keep
                regex: vault
              - source_labels:
                  - __meta_kubernetes_pod_container_name
                action: keep
                regex: vault
              # Surface useful metadata as labels.
              - source_labels: [__meta_kubernetes_namespace]
                target_label: namespace
              - source_labels: [__meta_kubernetes_pod_name]
                target_label: pod
              - source_labels: [__meta_kubernetes_pod_container_name]
                target_label: container
              # Container log path that promtail tails.
              - source_labels:
                  - __meta_kubernetes_pod_uid
                  - __meta_kubernetes_pod_container_name
                target_label: __path__
                separator: /
                replacement: /var/log/pods/*$1/*.log
        EOT
      }
    }

    # Tolerate any node taints on the small Vault cluster.
    tolerations = [{
      operator = "Exists"
    }]

    # Dev cluster — keep promtail's own resource footprint tiny.
    resources = {
      requests = { cpu = "50m", memory = "64Mi" }
      limits   = { cpu = "200m", memory = "128Mi" }
    }
  })]

  depends_on = [
    helm_release.vault,
    kubernetes_secret.loki_ingest_credentials,
  ]
}
