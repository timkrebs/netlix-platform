output "workspace_ids" {
  description = "Map of workspace name to workspace ID"
  value       = { for key, ws in tfe_workspace.this : key => ws.id }
}

output "workspace_urls" {
  description = "Map of workspace name to HCP Terraform URL"
  value = {
    for key, ws in tfe_workspace.this :
    key => "https://app.terraform.io/app/${var.tfc_organization}/workspaces/${ws.name}"
  }
}
