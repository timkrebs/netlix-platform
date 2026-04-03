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

# ─── Container Insights Alarms ───────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "pod_cpu_high" {
  alarm_name          = "${var.project}-${var.environment}-pod-cpu-high"
  alarm_description   = "Pod CPU utilization exceeds 80% in consul namespace"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "pod_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.eks_cluster_name
    Namespace   = "consul"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "pod_memory_high" {
  alarm_name          = "${var.project}-${var.environment}-pod-memory-high"
  alarm_description   = "Pod memory utilization exceeds 80% in consul namespace"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "pod_memory_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.eks_cluster_name
    Namespace   = "consul"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "pod_restart_high" {
  alarm_name          = "${var.project}-${var.environment}-pod-restarts"
  alarm_description   = "Pods restarting frequently in consul namespace"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "pod_number_of_container_restarts"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Maximum"
  threshold           = 3
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.eks_cluster_name
    Namespace   = "consul"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "node_cpu_high" {
  alarm_name          = "${var.project}-${var.environment}-node-cpu-high"
  alarm_description   = "EKS node CPU utilization exceeds 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "node_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.eks_cluster_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "node_memory_high" {
  alarm_name          = "${var.project}-${var.environment}-node-memory-high"
  alarm_description   = "EKS node memory utilization exceeds 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "node_memory_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.eks_cluster_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# ─── Container Insights Log Retention ────────────────────────────────────

resource "aws_cloudwatch_log_group" "container_insights_app" {
  name              = "/aws/containerinsights/${var.eks_cluster_name}/application"
  retention_in_days = var.log_retention_days
  tags              = { component = "monitoring" }
}

resource "aws_cloudwatch_log_group" "container_insights_host" {
  name              = "/aws/containerinsights/${var.eks_cluster_name}/host"
  retention_in_days = var.log_retention_days
  tags              = { component = "monitoring" }
}

resource "aws_cloudwatch_log_group" "container_insights_dataplane" {
  name              = "/aws/containerinsights/${var.eks_cluster_name}/dataplane"
  retention_in_days = var.log_retention_days
  tags              = { component = "monitoring" }
}

resource "aws_cloudwatch_log_group" "container_insights_performance" {
  name              = "/aws/containerinsights/${var.eks_cluster_name}/performance"
  retention_in_days = var.log_retention_days
  tags              = { component = "monitoring" }
}

# ─── CloudWatch Dashboard ────────────────────────────────────────────────

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project}-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      # ── Row 1: Cluster Overview ──────────────────────────────────────
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# ${var.project}-${var.environment} — Cluster Overview"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 8
        height = 6
        properties = {
          title   = "Node CPU Utilization"
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          metrics = [
            ["ContainerInsights", "node_cpu_utilization", "ClusterName", var.eks_cluster_name, { stat = "Average", label = "Average" }],
            ["...", { stat = "Maximum", label = "Max" }]
          ]
          period = 300
          yAxis  = { left = { min = 0, max = 100, label = "%" } }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 1
        width  = 8
        height = 6
        properties = {
          title   = "Node Memory Utilization"
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          metrics = [
            ["ContainerInsights", "node_memory_utilization", "ClusterName", var.eks_cluster_name, { stat = "Average", label = "Average" }],
            ["...", { stat = "Maximum", label = "Max" }]
          ]
          period = 300
          yAxis  = { left = { min = 0, max = 100, label = "%" } }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 1
        width  = 8
        height = 6
        properties = {
          title   = "Node Network (bytes/sec)"
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          metrics = [
            ["ContainerInsights", "node_network_total_bytes", "ClusterName", var.eks_cluster_name, { stat = "Average", label = "Total bytes/s" }]
          ]
          period = 300
        }
      },

      # ── Row 2: Pod Metrics (consul namespace) ───────────────────────
      {
        type   = "text"
        x      = 0
        y      = 7
        width  = 24
        height = 1
        properties = {
          markdown = "## Application Pods — consul namespace"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 8
        height = 6
        properties = {
          title   = "Pod CPU Utilization"
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          metrics = [
            ["ContainerInsights", "pod_cpu_utilization", "ClusterName", var.eks_cluster_name, "Namespace", "consul", "PodName", "web", { stat = "Average", label = "web" }],
            ["ContainerInsights", "pod_cpu_utilization", "ClusterName", var.eks_cluster_name, "Namespace", "consul", "PodName", "api", { stat = "Average", label = "api" }]
          ]
          period = 300
          yAxis  = { left = { min = 0, max = 100, label = "%" } }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 8
        width  = 8
        height = 6
        properties = {
          title   = "Pod Memory Utilization"
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          metrics = [
            ["ContainerInsights", "pod_memory_utilization", "ClusterName", var.eks_cluster_name, "Namespace", "consul", "PodName", "web", { stat = "Average", label = "web" }],
            ["ContainerInsights", "pod_memory_utilization", "ClusterName", var.eks_cluster_name, "Namespace", "consul", "PodName", "api", { stat = "Average", label = "api" }]
          ]
          period = 300
          yAxis  = { left = { min = 0, max = 100, label = "%" } }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 8
        width  = 8
        height = 6
        properties = {
          title   = "Pod Count (Running)"
          view    = "timeSeries"
          stacked = true
          region  = data.aws_region.current.name
          metrics = [
            ["ContainerInsights", "pod_number_of_running_pods", "ClusterName", var.eks_cluster_name, "Namespace", "consul", { stat = "Average", label = "consul" }],
            ["ContainerInsights", "pod_number_of_running_pods", "ClusterName", var.eks_cluster_name, "Namespace", "argocd", { stat = "Average", label = "argocd" }],
            ["ContainerInsights", "pod_number_of_running_pods", "ClusterName", var.eks_cluster_name, "Namespace", "kube-system", { stat = "Average", label = "kube-system" }]
          ]
          period = 300
        }
      },

      # ── Row 3: Pod Restarts + Network ───────────────────────────────
      {
        type   = "metric"
        x      = 0
        y      = 14
        width  = 8
        height = 6
        properties = {
          title   = "Container Restarts"
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          metrics = [
            ["ContainerInsights", "pod_number_of_container_restarts", "ClusterName", var.eks_cluster_name, "Namespace", "consul", { stat = "Sum", label = "consul" }]
          ]
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 14
        width  = 8
        height = 6
        properties = {
          title   = "Pod Network Rx/Tx (bytes/sec)"
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          metrics = [
            ["ContainerInsights", "pod_network_rx_bytes", "ClusterName", var.eks_cluster_name, "Namespace", "consul", { stat = "Average", label = "Rx" }],
            ["ContainerInsights", "pod_network_tx_bytes", "ClusterName", var.eks_cluster_name, "Namespace", "consul", { stat = "Average", label = "Tx" }]
          ]
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 14
        width  = 8
        height = 6
        properties = {
          title   = "Node Filesystem Utilization"
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          metrics = [
            ["ContainerInsights", "node_filesystem_utilization", "ClusterName", var.eks_cluster_name, { stat = "Average", label = "Average" }],
            ["...", { stat = "Maximum", label = "Max" }]
          ]
          period = 300
          yAxis  = { left = { min = 0, max = 100, label = "%" } }
        }
      },

      # ── Row 4: RDS Database ─────────────────────────────────────────
      {
        type   = "text"
        x      = 0
        y      = 20
        width  = 24
        height = 1
        properties = {
          markdown = "## RDS Database — ${var.rds_instance_id}"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 21
        width  = 8
        height = 6
        properties = {
          title   = "RDS CPU Utilization"
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.rds_instance_id, { stat = "Average" }]
          ]
          period = 300
          yAxis  = { left = { min = 0, max = 100, label = "%" } }
          annotations = {
            horizontal = [{ value = 80, label = "Alarm threshold", color = "#d62728" }]
          }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 21
        width  = 8
        height = 6
        properties = {
          title   = "RDS Free Storage (GB)"
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          metrics = [
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.rds_instance_id, { stat = "Average" }]
          ]
          period = 300
          annotations = {
            horizontal = [{ value = 5368709120, label = "Alarm threshold (5GB)", color = "#d62728" }]
          }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 21
        width  = 8
        height = 6
        properties = {
          title   = "RDS Connections"
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.rds_instance_id, { stat = "Average" }]
          ]
          period = 300
          annotations = {
            horizontal = [{ value = 80, label = "Alarm threshold", color = "#d62728" }]
          }
        }
      },

      # ── Row 5: VPC & Network ────────────────────────────────────────
      {
        type   = "text"
        x      = 0
        y      = 27
        width  = 24
        height = 1
        properties = {
          markdown = "## Network & Security"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 28
        width  = 12
        height = 6
        properties = {
          title   = "VPC Rejected Connections (Flow Logs)"
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          metrics = [
            ["${var.project}/${var.environment}/VPCFlowLogs", "RejectedConnectionCount", { stat = "Sum" }]
          ]
          period = 300
          annotations = {
            horizontal = [{ value = 100, label = "Alarm threshold", color = "#d62728" }]
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 28
        width  = 12
        height = 6
        properties = {
          title   = "RDS Read/Write Latency (ms)"
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          metrics = [
            ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", var.rds_instance_id, { stat = "Average", label = "Read" }],
            ["AWS/RDS", "WriteLatency", "DBInstanceIdentifier", var.rds_instance_id, { stat = "Average", label = "Write" }]
          ]
          period = 300
        }
      },

      # ── Row 6: Alarm Status ─────────────────────────────────────────
      {
        type   = "text"
        x      = 0
        y      = 34
        width  = 24
        height = 1
        properties = {
          markdown = "## Alarm Status"
        }
      },
      {
        type   = "alarm"
        x      = 0
        y      = 35
        width  = 24
        height = 3
        properties = {
          title = "All Alarms"
          alarms = [
            aws_cloudwatch_metric_alarm.rds_cpu.arn,
            aws_cloudwatch_metric_alarm.rds_free_storage.arn,
            aws_cloudwatch_metric_alarm.rds_connections.arn,
            aws_cloudwatch_metric_alarm.eks_node_not_ready.arn,
            aws_cloudwatch_metric_alarm.rejected_connections.arn,
            aws_cloudwatch_metric_alarm.pod_cpu_high.arn,
            aws_cloudwatch_metric_alarm.pod_memory_high.arn,
            aws_cloudwatch_metric_alarm.pod_restart_high.arn,
            aws_cloudwatch_metric_alarm.node_cpu_high.arn,
            aws_cloudwatch_metric_alarm.node_memory_high.arn,
          ]
        }
      }
    ]
  })
}

data "aws_region" "current" {}
