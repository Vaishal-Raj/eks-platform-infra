terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  
  }
  
#   backend "s3" {
#     bucket       = "tfstate-client-a-dev-264760299713"
#     key          = "bootstrap/state-backend/terraform.tfstate"
#     region       = "us-east-1"
#     encrypt      = true
#     use_lockfile = true
#   }
}