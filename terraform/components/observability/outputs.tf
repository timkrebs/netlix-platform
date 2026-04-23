output "namespace" {
  description = "Kubernetes namespace hosting Prometheus, Grafana, Loki, and Promtail."
  value       = kubernetes_namespace.observability.metadata[0].name
}

output "grafana_url" {
  description = "Public HTTPS URL for Grafana."
  value       = "https://grafana.${var.environment}.${var.domain}"
}

output "grafana_admin_secret" {
  description = "Name of the Kubernetes Secret synced from Vault that holds Grafana admin credentials."
  value       = local.grafana_admin_secret
}
