output "zone_id" {
  description = "Route53 hosted zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "nameservers" {
  description = "Route53 nameservers — update domain registrar with these"
  value       = aws_route53_zone.main.name_servers
}

output "certificate_arn" {
  description = "ACM wildcard certificate ARN for ALB Ingress"
  value       = aws_acm_certificate_validation.wildcard.certificate_arn
}
