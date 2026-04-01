output "endpoint" { value = module.rds.db_instance_endpoint }
output "port" { value = module.rds.db_instance_port }
output "admin_username" {
  value     = module.rds.db_instance_username
  sensitive = true
}
output "admin_password" {
  value     = random_password.master.result
  sensitive = true
}
output "db_name" { value = var.db_name }
