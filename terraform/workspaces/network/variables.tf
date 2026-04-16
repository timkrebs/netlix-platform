variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-central-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "azs" {
  description = "Availability zones"
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
}

variable "base_domain" {
  description = "Root domain managed by Route53 (e.g. netlix.dev)"
  type        = string
  default     = "netlix.dev"
}

variable "route53_zone_id" {
  description = "Pre-existing Route53 hosted zone ID"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging)"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "netlix"
}
