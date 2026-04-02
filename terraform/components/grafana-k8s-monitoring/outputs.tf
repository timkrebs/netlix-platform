output "namespace" {
  description = "Namespace where the k8s-monitoring stack is deployed"
  value       = helm_release.k8s_monitoring.namespace
}

output "otlp_grpc_endpoint" {
  description = "OTLP/gRPC endpoint for application instrumentation"
  value       = "http://grafana-k8s-monitoring-alloy-receiver.${helm_release.k8s_monitoring.namespace}.svc.cluster.local:4317"
}

output "otlp_http_endpoint" {
  description = "OTLP/HTTP endpoint for application instrumentation"
  value       = "http://grafana-k8s-monitoring-alloy-receiver.${helm_release.k8s_monitoring.namespace}.svc.cluster.local:4318"
}
