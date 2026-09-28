provider "aws" {
  region              = var.config.region
  allowed_account_ids = [var.config.account_id]

  default_tags {
    tags = merge(var.config.tags, {
      Project     = "eks-platform"
      ManagedBy   = "terraform"
      Client      = var.config.client_id
      Environment = var.config.environment
      Profile     = var.config.profile
      Layer       = "alb"
    })
  }
}