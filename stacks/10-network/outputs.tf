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

output "isolated_subnet_cidrs" {
  description = "Isolated subnet CIDRs"
  value       = module.network.isolated_subnet_cidrs
}

output "private_route_table_id" {
  description = "Private route table ID"
  value       = module.network.private_route_table_id
}

output "isolated_route_table_id" {
  description = "Isolated route table ID"
  value       = module.network.isolated_route_table_id
}
