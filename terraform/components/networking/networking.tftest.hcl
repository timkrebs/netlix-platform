variables {
  vpc_cidr    = "10.99.0.0/16"
  azs         = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  environment = "dev"
  project     = "netlix-test"
}

run "plan_dev_vpc" {
  command = plan

  assert {
    condition     = module.vpc.name == "netlix-test-dev"
    error_message = "VPC name should include project and environment"
  }
}

run "dev_uses_single_nat" {
  command = plan

  assert {
    condition     = var.environment == "dev"
    error_message = "Test environment should be dev"
  }
}

run "staging_uses_multi_nat" {
  command = plan

  variables {
    environment = "staging"
  }

  assert {
    condition     = var.environment == "staging"
    error_message = "Test environment should be staging"
  }
}
