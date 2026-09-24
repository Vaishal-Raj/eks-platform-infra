variable "name" {
  description = "Name prefix for resources eg: client-a-dev"
  type        = string
}

variable "vpc_cidr" {
  description = "The client's Cidr block"
  type        = string
}

variable "az_count" {
  description = "How many AZs to spread subnets across"
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "exclude_zone_ids" {
  description = "AZ IDs to skip, e.g. ones EKS doesn't support"
  type        = list(string)
  default     = []
}


# - A validation block rejects bad input at plan time, before anything reaches AWS.
# - can(...) returns false instead of an error when cidrhost is given something that isn't a CIDR.
# - exclude_zone_ids exists because of a us-east-1 catch: EKS can't place its control plane in AZ use1-az3. AZ names (us-east-1a) are shuffled per account, but AZ IDs (use1-az3) are the same for everyone, so you exclude by ID. Without this, M3's EKS cluster could fail to create.