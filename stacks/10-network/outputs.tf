# Read by later stacks (security, rds, eks) through terraform_remote_state.

output "vpc_id" {
  description = "VPC ID"
  value       = module.network.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.network.vpc_cidr
}

output "azs" {
  description = "AZ names used, in order"
  value       = module.network.azs
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.network.private_subnet_ids
}

output "private_subnet_cidrs" {
  description = "Private subnet CIDRs"
  value       = module.network.private_subnet_cidrs
}

output "isolated_subnet_ids" {
  description = "Isolated subnet IDs"
  value       = module.network.isolated_subnet_ids
}

output "private_route_table_id" {
  description = "Private route table ID"
  value       = module.network.private_route_table_id
}

output "vpce_security_group_id" {
  description = "Endpoint security group ID, or null when endpoints are disabled"
  value       = one(module.vpc_endpoints[*].security_group_id)
}

# - Because vpc_endpoints has count, it's now a list of zero or one modules. 
# one(module.vpc_endpoints[*].x) returns the value, or null when the list is empty. It's the same trick as the S3 endpoint inside the module.
# - Later stacks (security groups, RDS) read these outputs, so export everything they'll need.