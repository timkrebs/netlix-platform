module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.18"

  name               = var.cluster_name
  kubernetes_version = var.cluster_version
  vpc_id             = var.vpc_id
  subnet_ids         = var.private_subnet_ids

  endpoint_public_access       = length(var.cluster_endpoint_public_access_cidrs) > 0
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  endpoint_private_access      = true

  # EKS Auto Mode (compute_config / storage_config /
  # kubernetes_network_config.elastic_load_balancing) is intentionally
  # left at the v21 default (compute_config = null, no blocks emitted).
  # Setting it explicitly forces UpdateClusterConfig calls that AWS
  # rejects with "No changes needed for EKS Auto Mode configuration
  # provided" when the cluster is already in the target state. With
  # v6.15+ provider (aea201c fix) and v21 module, Computed+Default=false
  # schema semantics let refresh populate these fields from AWS so the
  # plan stays consistent without our help.

  # Allow other workloads in the same VPC to reach this cluster's API on
  # 443 over the private endpoint. Required for cross-cluster Vault
  # TokenReview (vault-cluster pods → app-cluster API). Default behavior
  # only allows the cluster's own nodes.
  security_group_additional_rules = var.cluster_api_extra_ingress_cidrs == null ? {} : {
    in_vpc_api_access = {
      description = "Allow other VPC workloads to reach the cluster API"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "ingress"
      cidr_blocks = var.cluster_api_extra_ingress_cidrs
    }
  }

  encryption_config = {
    provider_key_arn = aws_kms_key.eks.arn
    resources        = ["secrets"]
  }

  eks_managed_node_groups = {
    general = {
      name           = "${var.cluster_name}-ng"
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

  # Control plane logging — captures API, audit, authenticator, controller
  # manager, and scheduler logs to CloudWatch for security and debugging.
  enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  addons = {
    coredns            = { most_recent = true }
    kube-proxy         = { most_recent = true }
    vpc-cni            = { most_recent = true, service_account_role_arn = module.vpc_cni_irsa.iam_role_arn }
    aws-ebs-csi-driver = { most_recent = true, service_account_role_arn = module.ebs_csi_irsa.iam_role_arn }
    # metrics-server exposes the standard metrics.k8s.io API so
    # HorizontalPodAutoscalers can read pod CPU/memory. Required for
    # the shop-services HPAs in app/manifests/shop/*-hpa.yaml.
    metrics-server = { most_recent = true }
    amazon-cloudwatch-observability = {
      addon_version            = "v4.10.3-eksbuild.1"
      service_account_role_arn = module.cloudwatch_observability_irsa.iam_role_arn
    }
  }

  enable_cluster_creator_admin_permissions = false

  access_entries = {
    for arn in var.additional_admin_arns : arn => {
      principal_arn = arn
      type          = "STANDARD"
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

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
