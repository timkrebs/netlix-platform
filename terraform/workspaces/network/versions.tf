terraform {
  required_version = ">= 1.9"

  cloud {
    organization = "tim-krebs-org"

    workspaces {
      project = "netlix-platform"
      tags    = ["netlix", "network"]
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
