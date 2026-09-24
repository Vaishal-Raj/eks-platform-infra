terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Partial config: bucket/region come from build/<client>/<env>/backend.hcl,
  # key is passed by scripts/tf-stack.sh (network/terraform.tfstate).
  backend "s3" {}
}
