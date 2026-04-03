# Use the pre-existing Route53 hosted zone — never recreate it, as that
# changes the nameservers and breaks the registrar delegation.
data "aws_route53_zone" "main" {
  zone_id = var.zone_id
}

# ACM Wildcard Certificate
resource "aws_acm_certificate" "wildcard" {
  domain_name = "*.${var.cluster_env}.${var.domain}"

  subject_alternative_names = [
    "${var.cluster_env}.${var.domain}",
  ]

  validation_method = "DNS"

  tags = { component = "dns" }

  lifecycle {
    create_before_destroy = true
  }
}

# Route53 DNS Validation Records
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.wildcard.domain_validation_options :
    dvo.resource_record_name => dvo...
  }

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value[0].resource_record_name
  type    = each.value[0].resource_record_type
  ttl     = 60
  records = [each.value[0].resource_record_value]
}

# ACM Certificate Validation
resource "aws_acm_certificate_validation" "wildcard" {
  certificate_arn         = aws_acm_certificate.wildcard.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]

  timeouts {
    create = "120m"
  }
}
