terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # Partial config: bucket/region from build/<client>/<env>/backend.hcl,
  # key from tf-stack.sh (alb/terraform.tfstate).
  backend "s3" {}
}

