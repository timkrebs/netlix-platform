variable "hvn_id" {
  description = "HVN ID associated with the HCP Vault cluster"
  type        = string
}

variable "peer_vpc_id" {
  description = "AWS VPC ID to peer with"
  type        = string
}

variable "peer_account_id" {
  description = "AWS account ID that owns the VPC"
  type        = string
}

variable "peer_vpc_region" {
  description = "AWS region of the VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the AWS VPC"
  type        = string
}

variable "private_route_table_ids" {
  description = "Private route table IDs for adding HVN routes"
  type        = list(string)
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}
