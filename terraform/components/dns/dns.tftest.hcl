variables {
  domain      = "example.dev"
  cluster_env = "test"
}

run "plan_dns" {
  command = plan

  assert {
    condition     = aws_route53_zone.main.name == "example.dev"
    error_message = "Route53 zone should use the provided domain"
  }

  assert {
    condition     = aws_acm_certificate.wildcard.domain_name == "*.test.example.dev"
    error_message = "ACM cert should be a wildcard for the cluster environment subdomain"
  }
}
