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
