# ─── SNS Topic for Alarm Notifications ────────────────────────────────────

resource "aws_sns_topic" "alerts" {
  name = "${var.project}-${var.environment}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ─── VPC Flow Logs — Rejected Connections ─────────────────────────────────

locals {
  # Extract log group name from ARN: arn:aws:logs:region:account:log-group:NAME:*
  flow_log_group_name = regex("log-group:([^:]+)", var.vpc_flow_log_group_arn)[0]
}

resource "aws_cloudwatch_log_metric_filter" "rejected_connections" {
  name           = "${var.project}-${var.environment}-rejected-connections"
  log_group_name = local.flow_log_group_name
  pattern        = "[version, account_id, interface_id, srcaddr, dstaddr, srcport, dstport, protocol, packets, bytes, start, end, action=\"REJECT\", log_status]"

  metric_transformation {
    name          = "RejectedConnectionCount"
    namespace     = "${var.project}/${var.environment}/VPCFlowLogs"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "rejected_connections" {
  alarm_name          = "${var.project}-${var.environment}-high-rejected-connections"
  alarm_description   = "VPC flow logs show elevated rejected connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RejectedConnectionCount"
  namespace           = "${var.project}/${var.environment}/VPCFlowLogs"
  period              = 300
  statistic           = "Sum"
  threshold           = 100
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# ─── RDS Alarms ───────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.project}-${var.environment}-rds-high-cpu"
  alarm_description   = "RDS instance CPU utilization exceeds 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage" {
  alarm_name          = "${var.project}-${var.environment}-rds-low-storage"
  alarm_description   = "RDS free storage space is below 5 GB"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5368709120 # 5 GB in bytes
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "${var.project}-${var.environment}-rds-high-connections"
  alarm_description   = "RDS database connections exceed 80% of max"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# ─── EKS Cluster Alarms ──────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "eks_node_not_ready" {
  alarm_name          = "${var.project}-${var.environment}-eks-node-not-ready"
  alarm_description   = "EKS cluster has nodes in NotReady state"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "cluster_failed_node_count"
  namespace           = "AWS/EKS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.eks_cluster_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}
