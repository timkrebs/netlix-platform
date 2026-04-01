# Run once manually to bootstrap AWS OIDC trust for TFC Stacks
#
# Usage:
#   cd bootstrap
#   terraform init
#   terraform apply

terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

data "tls_certificate" "tfc" {
  url = "https://app.terraform.io"
}

resource "aws_iam_openid_connect_provider" "tfc" {
  url             = "https://app.terraform.io"
  client_id_list  = ["aws.workload.identity"]
  thumbprint_list = [data.tls_certificate.tfc.certificates[0].sha1_fingerprint]
}

resource "aws_iam_role" "tfc_dev" {
  name = "tfc-netlix-dev"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.tfc.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "app.terraform.io:aud" = "aws.workload.identity" }
        StringLike   = { "app.terraform.io:sub" = "organization:tim-krebs-org:project:netlix-platform:stack:netlix-platform-dev:*" }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "tfc_dev" {
  role       = aws_iam_role.tfc_dev.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role" "tfc_staging" {
  name = "tfc-netlix-staging"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.tfc.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "app.terraform.io:aud" = "aws.workload.identity" }
        StringLike   = { "app.terraform.io:sub" = "organization:tim-krebs-org:project:netlix-platform:stack:netlix-platform-staging:*" }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "tfc_staging" {
  role       = aws_iam_role.tfc_staging.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

output "dev_role_arn"     { value = aws_iam_role.tfc_dev.arn }
output "staging_role_arn" { value = aws_iam_role.tfc_staging.arn }
output "oidc_provider_arn" { value = aws_iam_openid_connect_provider.tfc.arn }
