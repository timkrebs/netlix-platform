variable "domain" {
  description = "Root domain managed by Route53 (e.g. netlix.dev)"
  type        = string
}

variable "cluster_env" {
  description = "Environment label used as subdomain layer: <svc>.<cluster_env>.<domain>"
  type        = string
}
