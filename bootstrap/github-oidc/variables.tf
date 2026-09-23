variable "region" {
  description = "AWS region for the provider"
  type        = string
  default     = "us-east-1"
}

variable "github_owner" {
  description = "GitHub user or org that owns the repo"
  type        = string
  default     = "Vaishal-Raj"
}

variable "github_repo" {
  description = "Infra repo name"
  type        = string
  default     = "eks-platform-infra"
}

variable "environments" {
  description = "GitHub Environments that get their own apply role"
  type        = set(string)
  default     = ["dev", "staging", "prod"]
}

variable "state_bucket" {
  description = "Terraform state bucket the plan role may lock"
  type        = string
  default     = "tfstate-client-a-dev-264760299713"
}