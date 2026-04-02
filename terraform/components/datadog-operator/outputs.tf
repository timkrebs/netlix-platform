output "namespace" {
  value = kubernetes_namespace_v1.datadog.metadata[0].name
}
