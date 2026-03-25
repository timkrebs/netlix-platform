# Temporary import blocks for adopting existing AWS resources into Stacks state.
# Remove after the first successful apply.

import {
  to = module.eks.aws_eks_cluster.this[0]
  id = var.cluster_name
}

import {
  to = module.eks.aws_cloudwatch_log_group.this[0]
  id = "/aws/eks/${var.cluster_name}/cluster"
}

import {
  to = module.eks.module.kms.aws_kms_alias.this["cluster"]
  id = "alias/eks/${var.cluster_name}"
}

import {
  to = aws_kms_alias.eks
  id = "alias/${var.cluster_name}-eks"
}
