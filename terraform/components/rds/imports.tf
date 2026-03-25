# Temporary import blocks for adopting existing AWS/RDS resources into Stacks state.
# Remove after the first successful apply.

import {
  to = module.rds.module.db_instance.aws_iam_role.enhanced_monitoring[0]
  id = "${var.project}-rds-monitoring"
}

import {
  to = module.rds.module.db_instance.aws_db_instance.this[0]
  id = "${var.project}-${var.environment}"
}

import {
  to = aws_db_subnet_group.this
  id = "${var.project}-${var.environment}"
}
