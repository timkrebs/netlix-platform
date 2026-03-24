policy "require-mandatory-tags" {
  source            = "./policies/require-mandatory-tags.sentinel"
  enforcement_level = "hard-mandatory"
}

policy "enforce-encryption-at-rest" {
  source            = "./policies/enforce-encryption-at-rest.sentinel"
  enforcement_level = "hard-mandatory"
}

policy "restrict-instance-types" {
  source            = "./policies/restrict-instance-types.sentinel"
  enforcement_level = "soft-mandatory"
}

policy "enforce-cost-limit" {
  source            = "./policies/enforce-cost-limit.sentinel"
  enforcement_level = "soft-mandatory"
}

policy "no-public-s3-buckets" {
  source            = "./policies/no-public-s3-buckets.sentinel"
  enforcement_level = "hard-mandatory"
}

policy "require-vpc-flow-logs" {
  source            = "./policies/require-vpc-flow-logs.sentinel"
  enforcement_level = "advisory"
}
