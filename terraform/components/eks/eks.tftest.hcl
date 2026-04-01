variables {
  cluster_name                         = "netlix-test"
  cluster_version                      = "1.31"
  vpc_id                               = "vpc-test123"
  private_subnet_ids                   = ["subnet-a", "subnet-b", "subnet-c"]
  node_instance_types                  = ["m6i.large"]
  node_desired_size                    = 2
  node_min_size                        = 1
  node_max_size                        = 3
  environment                          = "dev"
  project                              = "netlix-test"
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]
}

run "plan_eks_public_access" {
  command = plan

  assert {
    condition     = length(var.cluster_endpoint_public_access_cidrs) > 0
    error_message = "Dev should have public access CIDRs defined"
  }
}

run "plan_eks_private_only" {
  command = plan

  variables {
    cluster_endpoint_public_access_cidrs = []
  }

  assert {
    condition     = length(var.cluster_endpoint_public_access_cidrs) == 0
    error_message = "Staging/prod should have empty CIDRs for private-only"
  }
}
