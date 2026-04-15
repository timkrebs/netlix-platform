output "namespace" {
  description = "cert-manager namespace (dependency anchor for downstream components)"
  value       = helm_release.cert_manager.namespace
}
