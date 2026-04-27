resource "random_password" "master" {
  length  = 32
  special = false
}

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier = "${var.project}-${var.environment}"

  engine               = "postgres"
  engine_version       = var.db_engine_version
  family               = "postgres16"
  major_engine_version = "16"
  instance_class       = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 100

  db_name  = var.db_name
  username = "netlixadmin"
  password = random_password.master.result
  port     = 5432

  manage_master_user_password = false

  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  create_db_subnet_group = false
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  backup_retention_period = var.environment == "dev" ? 3 : 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  monitoring_interval                   = 60
  monitoring_role_name                  = "${var.project}-${var.environment}-rds-monitoring"
  create_monitoring_role                = true
  performance_insights_enabled          = var.environment == "prod"
  performance_insights_retention_period = 7

  multi_az            = var.environment != "dev"
  deletion_protection = var.environment != "dev"
  skip_final_snapshot = var.environment == "dev"

  tags = { component = "rds" }
}

resource "aws_kms_key" "rds" {
  description             = "Netlix RDS encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = { component = "rds" }
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-${var.environment}"
  subnet_ids = var.private_subnet_ids
  tags       = { component = "rds" }
}

resource "aws_security_group" "rds" {
  name_prefix = "${var.project}-rds-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_security_group]
    description     = "PostgreSQL from EKS"
  }

  dynamic "ingress" {
    for_each = var.hvn_cidr_block != "" ? [var.hvn_cidr_block] : []
    content {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
      description = "PostgreSQL from HCP Vault HVN"
    }
  }

  # No egress rules — RDS does not need outbound internet access.
  # Enhanced Monitoring uses a VPC endpoint or the monitoring service role.

  tags = { component = "rds" }
}
