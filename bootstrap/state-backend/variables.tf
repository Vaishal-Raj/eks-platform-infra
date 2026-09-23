variable "region" {
  description = "AWS region for the state bucket"
  type        = string
  default     = "us-east-1"
}

variable "client_id" {
  description = "Client this state belongs to"
  type        = string
  default     = "client-a"
}

variable "environment" {
  description = "dev, stg or prod"
  type        = string
  default     = "dev"
}