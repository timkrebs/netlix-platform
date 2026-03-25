# Import existing resources into Stacks state.
# These blocks can be removed after the first successful apply.

import {
  to = module.rds.module.db_instance.aws_iam_role.enhanced_monitoring[0]
  id = "${var.project}-rds-monitoring"
}

import {
  to = aws_db_subnet_group.this
  id = "${var.project}-${var.environment}"
}
