provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      environment = var.environment
      project     = var.project
      managed_by  = "terraform"
    }
  }
}

provider "hcp" {
  project_id = var.hcp_project_id
}

provider "vault" {
  address   = var.vault_address
  token     = var.vault_token
  namespace = "admin"
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
    token                  = module.eks.cluster_token
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  token                  = module.eks.cluster_token
}
