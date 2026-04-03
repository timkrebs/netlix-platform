module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  vpc_id          = var.vpc_id
  subnet_ids      = var.private_subnet_ids

  cluster_endpoint_public_access       = length(var.cluster_endpoint_public_access_cidrs) > 0
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  cluster_endpoint_private_access      = true

  cluster_encryption_config = {
    provider_key_arn = aws_kms_key.eks.arn
    resources        = ["secrets"]
  }

  eks_managed_node_groups = {
    general = {
      name           = "${var.cluster_name}-general"
      instance_types = var.node_instance_types
      desired_size   = var.node_desired_size
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      ami_type       = "AL2023_x86_64_STANDARD"

      labels = {
        role        = "general"
        environment = var.environment
      }
    }
  }

  enable_irsa = true

  # Explicitly disable EKS Auto Mode (required by AWS provider >= 5.75)
  cluster_compute_config = {
    enabled = false
  }

  cluster_addons = {
    coredns            = { most_recent = true }
    kube-proxy         = { most_recent = true }
    vpc-cni            = { most_recent = true, service_account_role_arn = module.vpc_cni_irsa.iam_role_arn }
    aws-ebs-csi-driver = { most_recent = true, service_account_role_arn = module.ebs_csi_irsa.iam_role_arn }
    amazon-cloudwatch-observability = {
      addon_version            = "v4.10.3-eksbuild.1"
      service_account_role_arn = module.cloudwatch_observability_irsa.iam_role_arn
    }
  }

  enable_cluster_creator_admin_permissions = true

  tags = { component = "eks" }
}

resource "aws_kms_key" "eks" {
  description             = "Netlix EKS secrets encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = { component = "eks" }
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.cluster_name}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}
