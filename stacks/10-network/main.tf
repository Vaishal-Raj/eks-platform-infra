locals {
  name = "${var.config.client_id}-${var.config.environment}"
}

module "network" {
  source = "git::https://github.com/Vaishal-Raj/eks-platform-modules.git//modules/network?ref=v0.3.0"

  name             = local.name
  vpc_cidr         = var.config.vpc_cidr
  az_count         = var.config.network.az_count
  exclude_zone_ids = var.config.exclude_zone_ids

  # Platform decision: every client runs EKS, whose Load Balancer Controller
  # places internal ALBs in subnets carrying this tag.
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

module "vpc_endpoints" {
  source = "git::https://github.com/Vaishal-Raj/eks-platform-modules.git//modules/vpc-endpoints?ref=v0.3.0"
  count  = var.config.endpoints.enabled ? 1 : 0

  name               = local.name
  vpc_id             = module.network.vpc_id
  subnet_ids         = module.network.private_subnet_ids
  allowed_cidrs      = module.network.private_subnet_cidrs
  route_table_ids    = [module.network.private_route_table_id]
  interface_services = var.config.endpoints.interface_services
  enable_s3_gateway  = var.config.endpoints.enable_s3_gateway
}