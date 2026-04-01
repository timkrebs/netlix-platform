variables {
  vpc_id             = "vpc-test123"
  private_subnet_ids = ["subnet-a", "subnet-b"]
  db_instance_class  = "db.t4g.medium"
  db_name            = "testdb"
  db_engine_version  = "16.6"
  eks_security_group = "sg-test123"
  hvn_cidr_block     = ""
  environment        = "dev"
  project            = "netlix-test"
}

run "dev_allows_deletion" {
  command = plan

  assert {
    condition     = var.environment == "dev"
    error_message = "Test should be running in dev"
  }
}

run "staging_protects_deletion" {
  command = plan

  variables {
    environment = "staging"
  }

  assert {
    condition     = var.environment != "dev"
    error_message = "Staging should enable deletion protection"
  }
}
