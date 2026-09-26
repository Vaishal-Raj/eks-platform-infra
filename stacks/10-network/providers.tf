provider "aws" {
  region              = var.config.region
  allowed_account_ids = [var.config.account_id] # refuse to run against the wrong account

  default_tags {
    tags = merge(var.config.tags, {
      Project     = "poc-gvr"
      ManagedBy   = "terraform"
      Client      = var.config.client_id
      Environment = var.config.environment
      Profile     = var.config.profile
      Layer       = "network"
    })
  }
}

# - allowed_account_ids is a safety net. If you're logged in to the wrong AWS account, Terraform refuses to run instead of building client-a's VPC somewhere else.
# - default_tags puts every one of these tags on every resource both modules create. So there's no need to pass tags into the modules.
# - Profile tag: in the console you can now filter "all resources built from the small profile". It's handy for cost reports.