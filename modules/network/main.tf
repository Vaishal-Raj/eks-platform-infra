data "aws_availability_zones" "available" {
  state            = "available"
  exclude_zone_ids = var.exclude_zone_ids
}

locals {
  azs              = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  private_subnets  = { for i, az in local.azs : az => cidrsubnet(var.vpc_cidr, 4, i) }
  isolated_subnets = { for i, az in local.azs : az => cidrsubnet(var.vpc_cidr, 8, 48 + i) }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = var.name
  }
}

resource "aws_subnet" "private" {
  for_each          = local.private_subnets
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = {
    Name                              = "${var.name}-private-${each.key}"
    Tier                              = "private"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "isolated" {
  for_each = local.isolated_subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = {
    Name = "${var.name}-isolated-${each.key}"
    Tier = "isolated"
  }
}


# - for_each over a map, not count over a list. Resources get addresses like aws_subnet.private["us-east-1a"]. With a list they'd be [0] and [1], and inserting an item would shift the numbers, so Terraform would destroy and recreate subnets.
# - kubernetes.io/role/internal-elb = 1 tells the AWS Load Balancer Controller (M3) where to put the internal ALB.


resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-private" }
}

resource "aws_route_table" "isolated" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-isolated" }
}


resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "isolated" {
  for_each = aws_subnet.isolated

  subnet_id      = each.value.id
  route_table_id = aws_route_table.isolated.id
}

# - There's one private table for both AZs. Classic designs have one per AZ because each AZ has its own NAT gateway; no NAT here.
# - The isolated tier gets its own table, so the S3 gateway route added to the private tier never reaches RDS.
