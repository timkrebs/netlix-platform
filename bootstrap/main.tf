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

resource "aws_iam_role_policy" "tfc_dev" {
  name = "tfc-netlix-dev-scoped"
  role = aws_iam_role.tfc_dev.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Networking"
        Effect   = "Allow"
        Action   = ["ec2:*", "elasticloadbalancing:*"]
        Resource = "*"
      },
      {
        Sid      = "EKS"
        Effect   = "Allow"
        Action   = ["eks:*"]
        Resource = "*"
      },
      {
        Sid      = "RDS"
        Effect   = "Allow"
        Action   = ["rds:*"]
        Resource = "*"
      },
      {
        Sid      = "DNS"
        Effect   = "Allow"
        Action   = ["route53:*", "acm:*"]
        Resource = "*"
      },
      {
        Sid      = "IAM"
        Effect   = "Allow"
        Action   = ["iam:*"]
        Resource = "*"
      },
      {
        Sid      = "KMS"
        Effect   = "Allow"
        Action   = ["kms:*"]
        Resource = "*"
      },
      {
        Sid      = "Observability"
        Effect   = "Allow"
        Action   = ["logs:*", "cloudwatch:*", "sns:*"]
        Resource = "*"
      },
      {
        Sid      = "STS"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity", "sts:AssumeRole"]
        Resource = "*"
      },
    ]
  })
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

resource "aws_iam_role_policy" "tfc_staging" {
  name = "tfc-netlix-staging-scoped"
  role = aws_iam_role.tfc_staging.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Networking"
        Effect   = "Allow"
        Action   = ["ec2:*", "elasticloadbalancing:*"]
        Resource = "*"
      },
      {
        Sid      = "EKS"
        Effect   = "Allow"
        Action   = ["eks:*"]
        Resource = "*"
      },
      {
        Sid      = "RDS"
        Effect   = "Allow"
        Action   = ["rds:*"]
        Resource = "*"
      },
      {
        Sid      = "DNS"
        Effect   = "Allow"
        Action   = ["route53:*", "acm:*"]
        Resource = "*"
      },
      {
        Sid      = "IAM"
        Effect   = "Allow"
        Action   = ["iam:*"]
        Resource = "*"
      },
      {
        Sid      = "KMS"
        Effect   = "Allow"
        Action   = ["kms:*"]
        Resource = "*"
      },
      {
        Sid      = "Observability"
        Effect   = "Allow"
        Action   = ["logs:*", "cloudwatch:*", "sns:*"]
        Resource = "*"
      },
      {
        Sid      = "STS"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity", "sts:AssumeRole"]
        Resource = "*"
      },
    ]
  })
}

# ─── Outputs ─────────────────────────────────────────────────────────────

output "dev_role_arn" { value = aws_iam_role.tfc_dev.arn }
output "staging_role_arn" { value = aws_iam_role.tfc_staging.arn }
output "oidc_provider_arn" { value = aws_iam_openid_connect_provider.tfc.arn }
