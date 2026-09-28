provider "aws" {
  region              = var.config.region
  allowed_account_ids = [var.config.account_id]

  ignore_tags {
    keys         = ["Owner"]
    key_prefixes = ["c7n-"]
  }
  
  default_tags {
    tags = merge(var.config.tags, {
      Project     = "poc-gvr"
      ManagedBy   = "terraform"
      Client      = var.config.client_id
      Environment = var.config.environment
      Profile     = var.config.profile
      Layer       = "alb"
    })
  }
}