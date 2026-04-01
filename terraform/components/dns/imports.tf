# One-time imports — remove this file after successful apply.
#
# Imports the pre-existing Route53 hosted zone (the one the domain registrar
# delegates to) so Terraform manages it instead of creating a duplicate.

import {
  to = aws_route53_zone.main
  id = "Z03825243OZJVWRUDJ5T"
}

import {
  to = aws_route53_record.cert_validation["_5f46b2b37ecd8b769d5d42938cfb7018.dev.netlix.dev."]
  id = "Z03825243OZJVWRUDJ5T__5f46b2b37ecd8b769d5d42938cfb7018.dev.netlix.dev._CNAME"
}
