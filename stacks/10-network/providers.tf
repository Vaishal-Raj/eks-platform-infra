provider "aws" {
  region              = var.config.region
  allowed_account_ids = [var.config.account_id] # refuse to run against the wrong account

  default_tags {
    tags = merge(var.config.tags, {
      Client      = var.config.client_id
      Environment = var.config.environment
      Layer       = "network"
    })
  }
}
