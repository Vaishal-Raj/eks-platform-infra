output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "azs" {
  value = local.azs
}

output "private_subnet_ids" {
  value = [for s in aws_subnet.private : s.id]
}

output "private_subnet_cidrs" {
  value = [for s in aws_subnet.private : s.cidr_block]
}

output "isolated_subnet_ids" {
  value = [for s in aws_subnet.isolated : s.id]
}

output "private_route_table_id" {
  value = aws_route_table.private.id
}

output "isolated_route_table_id" {
  value = aws_route_table.isolated.id
}