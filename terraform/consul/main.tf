provider "aws" {
  region = var.region

  default_tags {
    tags = {
      environment = var.environment
      project     = "netlix"
      managed_by  = "terraform"
    }
  }
}

data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}

data "aws_caller_identity" "current" {}

# OIDC provider for IRSA
data "aws_iam_openid_connect_provider" "eks" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

# Route53 zone (created by terraform/dns module)
data "aws_route53_zone" "main" {
  name         = var.base_domain
  private_zone = false
}

# Wildcard ACM certificate (must already be ISSUED before consul apply)
data "aws_acm_certificate" "wildcard" {
  domain      = "*.${var.cluster_env}.${var.base_domain}"
  types       = ["AMAZON_ISSUED"]
  most_recent = true
  statuses    = ["ISSUED"]
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# ── AWS Load Balancer Controller IRSA ───────────────────────────────────────

# Official IAM policy for LBC v2.8.3
data "http" "lbc_iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.8.3/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "lbc" {
  name        = "AWSLoadBalancerControllerIAMPolicy-${var.cluster_name}"
  description = "IAM policy for AWS Load Balancer Controller on ${var.cluster_name}"
  policy      = data.http.lbc_iam_policy.response_body
}

data "aws_iam_policy_document" "lbc_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.eks.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lbc" {
  name               = "eks-${var.cluster_name}-lbc"
  assume_role_policy = data.aws_iam_policy_document.lbc_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lbc" {
  role       = aws_iam_role.lbc.name
  policy_arn = aws_iam_policy.lbc.arn
}

resource "helm_release" "lbc" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.8.3"
  namespace  = "kube-system"

  timeout = 300

  set {
    name  = "clusterName"
    value = var.cluster_name
  }
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.lbc.arn
  }
  set {
    name  = "region"
    value = var.region
  }
  set {
    name  = "vpcId"
    value = data.aws_eks_cluster.cluster.vpc_config[0].vpc_id
  }
}

# ── ExternalDNS IRSA ─────────────────────────────────────────────────────────

data "aws_iam_policy_document" "external_dns" {
  statement {
    sid     = "Route53ChangeRecords"
    effect  = "Allow"
    actions = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${data.aws_route53_zone.main.zone_id}"]
  }
  statement {
    sid    = "Route53ListZones"
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "external_dns" {
  name        = "ExternalDNSIAMPolicy-${var.cluster_name}"
  description = "IAM policy for ExternalDNS on ${var.cluster_name}"
  policy      = data.aws_iam_policy_document.external_dns.json
}

data "aws_iam_policy_document" "external_dns_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.eks.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:external-dns"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "external_dns" {
  name               = "eks-${var.cluster_name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.external_dns_assume_role.json
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  role       = aws_iam_role.external_dns.name
  policy_arn = aws_iam_policy.external_dns.arn
}

resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = "1.14.5"
  namespace  = "kube-system"

  timeout    = 300
  depends_on = [helm_release.lbc]

  set {
    name  = "provider"
    value = "aws"
  }
  set {
    name  = "aws.region"
    value = var.region
  }
  set {
    name  = "domainFilters[0]"
    value = var.base_domain
  }
  set {
    name  = "policy"
    value = "sync"
  }
  set {
    name  = "txtOwnerId"
    value = "${var.cluster_name}-${var.cluster_env}"
  }
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = "external-dns"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.external_dns.arn
  }
  set {
    name  = "sources[0]"
    value = "service"
  }
  set {
    name  = "sources[1]"
    value = "ingress"
  }
}

# ── Vault namespace ───────────────────────────────────────────────────────────

resource "kubernetes_namespace" "vault" {
  metadata {
    name = "vault"
  }
}

# ── Vault Agent Injector (external mode — no Vault server in cluster) ────────

resource "helm_release" "vault" {
  name       = "vault"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  version    = "0.29.1"
  namespace  = kubernetes_namespace.vault.metadata[0].name

  timeout = 300

  set {
    name  = "server.enabled"
    value = "false"
  }

  set {
    name  = "injector.enabled"
    value = "true"
  }

  set {
    name  = "injector.externalVaultAddr"
    value = var.vault_addr
  }

  set {
    name  = "injector.authPath"
    value = "auth/kubernetes"
  }

  # Use port 8443 instead of default 8080 — the EKS node security group
  # only allows the control-plane SG on specific ports (443, 4443, 6443,
  # 8443, 9443, 10250, 10251).  Port 8080 is blocked, which prevents the
  # API server from reaching the webhook and silently skips injection
  # (failurePolicy: Ignore).
  set {
    name  = "injector.port"
    value = "8443"
  }

  set {
    name  = "global.externalVaultAddr"
    value = var.vault_addr
  }
}

# ── Consul namespace ─────────────────────────────────────────────────────────

resource "kubernetes_namespace" "consul" {
  metadata {
    name = "consul"
    labels = {
      "vault-injection" = "enabled"
    }
  }
}

# ── Consul Helm Release ──────────────────────────────────────────────────────

resource "helm_release" "consul" {
  name       = "consul"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "consul"
  version    = var.consul_chart_version
  namespace  = kubernetes_namespace.consul.metadata[0].name

  timeout = 600

  depends_on = [helm_release.vault, helm_release.lbc, helm_release.external_dns]

  values = [
    templatefile("${path.module}/values.yaml.tftpl", {
      consul_version  = var.consul_version
      datacenter      = var.consul_datacenter
      replicas        = var.consul_replicas
      vault_addr      = var.vault_addr
      vault_namespace = var.vault_namespace
      cert_arn        = data.aws_acm_certificate.wildcard.arn
      base_domain     = var.base_domain
      cluster_env     = var.cluster_env
    })
  ]
}
