locals {
  default_tags = merge(var.tags, {
    managed_by = "terraform"
    project    = var.project
  })
}
