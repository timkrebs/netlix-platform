# Import existing resources into Stacks state.
# These blocks can be removed after the first successful apply.

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
