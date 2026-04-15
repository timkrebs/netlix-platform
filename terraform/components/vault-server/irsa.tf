# ─── IRSA role for Vault pods to access AWS KMS ────────────────────────────

module "vault_kms_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-vault-kms"

  role_policy_arns = {
    vault_kms = aws_iam_policy.vault_kms.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["vault:vault"]
    }
  }
}

resource "aws_iam_policy" "vault_kms" {
  name        = "${var.cluster_name}-vault-kms"
  description = "Allow Vault to use KMS for auto-unseal"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey",
        ]
        Resource = [aws_kms_key.vault_unseal.arn]
      }
    ]
  })
}
