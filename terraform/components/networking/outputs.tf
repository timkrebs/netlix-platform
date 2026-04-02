output "vpc_id" { value = module.vpc.vpc_id }
output "private_subnet_ids" { value = module.vpc.private_subnets }
output "public_subnet_ids" { value = module.vpc.public_subnets }
output "vpc_cidr_block" { value = module.vpc.vpc_cidr_block }
output "private_route_table_ids" { value = module.vpc.private_route_table_ids }
output "public_route_table_ids" { value = module.vpc.public_route_table_ids }
output "vpc_owner_id" { value = module.vpc.vpc_owner_id }
output "flow_log_cloudwatch_log_group_arn" {
  description = "CloudWatch log group ARN for VPC flow logs"
  value       = module.vpc.vpc_flow_log_destination_arn
}
