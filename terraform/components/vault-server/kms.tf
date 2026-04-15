# ─── AWS KMS key for Vault auto-unseal ─────────────────────────────────────

resource "aws_kms_key" "vault_unseal" {
  description             = "Vault auto-unseal key for ${var.project}-${var.environment}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccountRoot"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowVaultIRSA"
        Effect = "Allow"
        Principal = {
          AWS = module.vault_kms_irsa.iam_role_arn
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey",
        ]
        Resource = "*"
      }
    ]
  })

  tags = { component = "vault-server" }
}

resource "aws_kms_alias" "vault_unseal" {
  name          = "alias/${var.project}-${var.environment}-vault-unseal"
  target_key_id = aws_kms_key.vault_unseal.key_id
}

data "aws_caller_identity" "current" {}
