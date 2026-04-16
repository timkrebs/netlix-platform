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

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  token                  = module.eks.cluster_token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
    token                  = module.eks.cluster_token
  }
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  token                  = module.eks.cluster_token
  load_config_file       = false
}

# Vault provider connects externally to the Vault cluster's ALB.
# Uses a variable (not module output) to avoid circular dependency.
provider "vault" {
  address          = var.vault_address
  token            = var.vault_root_token
  skip_child_token = true
}
