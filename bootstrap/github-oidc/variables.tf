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

variable "github_owner_id" {
  description = "Numeric GitHub owner ID (part of the immutable OIDC subject)"
  type        = string
  default     = "114581488"
}

variable "github_repo_id" {
  description = "Numeric GitHub repo ID (part of the immutable OIDC subject)"
  type        = string
  default     = "1383398911"
}

variable "environments" {
  description = "GitHub Environments that get their own apply role"
  type        = set(string)
  default     = ["dev"]
}
