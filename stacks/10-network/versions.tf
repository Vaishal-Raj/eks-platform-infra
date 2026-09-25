terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # Partial config: bucket/region come from build/<client>/<env>/backend.hcl,
  # and the key is passed at init time (network/terraform.tfstate).
  backend "s3" {}

}