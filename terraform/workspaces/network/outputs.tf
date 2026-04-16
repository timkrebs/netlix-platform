output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.networking.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.networking.public_subnet_ids
}

output "vpc_cidr_block" {
  description = "VPC CIDR block"
  value       = module.networking.vpc_cidr_block
}

output "flow_log_cloudwatch_log_group_arn" {
  description = "CloudWatch log group ARN for VPC flow logs"
  value       = module.networking.flow_log_cloudwatch_log_group_arn
}

output "zone_id" {
  description = "Route53 hosted zone ID"
  value       = module.dns.zone_id
}

output "nameservers" {
  description = "Route53 nameservers for registrar delegation"
  value       = module.dns.nameservers
}

output "certificate_arn" {
  description = "ACM wildcard certificate ARN"
  value       = module.dns.certificate_arn
}
