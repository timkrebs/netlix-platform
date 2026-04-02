variable "environment" {
  description = "Deployment environment (dev, staging)"
  type        = string
}

variable "project" {
  description = "Project name for resource naming"
  type        = string
}

variable "vpc_flow_log_group_arn" {
  description = "CloudWatch log group ARN for VPC flow logs"
  type        = string
}

variable "rds_instance_id" {
  description = "RDS instance identifier for CloudWatch alarms"
  type        = string
}

variable "eks_cluster_name" {
  description = "EKS cluster name for CloudWatch alarms"
  type        = string
}

variable "alert_email" {
  description = "Email address for alarm notifications (optional — leave empty to skip SNS subscription)"
  type        = string
  default     = ""
}
