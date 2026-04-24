terraform {
  required_version = ">= 1.9"

  required_providers {
    hcp = {
      source  = "hashicorp/hcp"
      version = "~> 0.100"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.83"
    }
  }
}
