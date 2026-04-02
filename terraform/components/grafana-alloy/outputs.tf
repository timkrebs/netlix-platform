output "alloy_namespace" {
  description = "Namespace where Grafana Alloy is deployed"
  value       = helm_release.alloy.namespace
}
