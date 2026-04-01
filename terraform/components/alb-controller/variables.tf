variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "lb_controller_role_arn" {
  description = "IAM role ARN for the ALB controller service account (IRSA)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the ALB will be created"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}
