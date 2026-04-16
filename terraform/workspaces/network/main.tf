# ─── Networking (VPC + subnets + NAT + flow logs) ─────────────────────────

module "networking" {
  source = "../../components/networking"

  vpc_cidr    = var.vpc_cidr
  azs         = var.azs
  environment = var.environment
  project     = var.project
}

# ─── DNS (Route53 + ACM wildcard certificate) ─────────────────────────────

module "dns" {
  source = "../../components/dns"

  domain      = var.base_domain
  cluster_env = var.environment
  zone_id     = var.route53_zone_id
}
