# Temporary import blocks for adopting existing resources into state.
# Remove after the first successful apply.

# ─── EKS ────────────────────────────────────────────────────────────────────

import {
  to = module.eks.module.eks.aws_eks_cluster.this[0]
  id = var.cluster_name
}

import {
  to = module.eks.module.eks.aws_cloudwatch_log_group.this[0]
  id = "/aws/eks/${var.cluster_name}/cluster"
}

import {
  to = module.eks.module.eks.module.kms.aws_kms_alias.this["cluster"]
  id = "alias/eks/${var.cluster_name}"
}

import {
  to = module.eks.aws_kms_alias.eks
  id = "alias/${var.cluster_name}-eks"
}

# ─── RDS ────────────────────────────────────────────────────────────────────

import {
  to = module.rds.module.rds.module.db_instance.aws_iam_role.enhanced_monitoring[0]
  id = "${var.project}-rds-monitoring"
}

import {
  to = module.rds.module.rds.module.db_instance.aws_db_instance.this[0]
  id = "${var.project}-${var.environment}"
}

import {
  to = module.rds.aws_db_subnet_group.this
  id = "${var.project}-${var.environment}"
}

# ─── Vault Config ───────────────────────────────────────────────────────────

import {
  to = module.vault_config.vault_auth_backend.kubernetes
  id = "kubernetes/netlix-${var.environment}"
}

import {
  to = module.vault_config.vault_auth_backend.userpass
  id = "userpass"
}

import {
  to = module.vault_config.vault_mount.database
  id = "database"
}

import {
  to = module.vault_config.vault_mount.kv
  id = "secret"
}

import {
  to = module.vault_config.vault_mount.pki
  id = "pki"
}

import {
  to = module.vault_config.vault_mount.pki_int
  id = "pki_int"
}
