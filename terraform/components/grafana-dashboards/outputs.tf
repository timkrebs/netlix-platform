output "folder_uid" {
  description = "Grafana folder UID containing the dashboards"
  value       = grafana_folder.netlix.uid
}

output "dashboard_urls" {
  description = "Map of dashboard names to their URLs"
  value = {
    cluster_overview     = grafana_dashboard.cluster_overview.url
    application_services = grafana_dashboard.application_services.url
    logs                 = grafana_dashboard.logs.url
  }
}
