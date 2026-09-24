module "network" {
  source = "git::https://github.com/Vaishal-Raj/eks-platform-modules.git//modules/network?ref=v0.2.0"

  name             = "${var.config.client_id}-${var.config.environment}"
  vpc_cidr         = var.config.vpc_cidr
  az_count         = var.config.network.az_count
  exclude_zone_ids = var.config.network.exclude_zone_ids

  # Platform decision, not a client one: every client runs EKS, whose
  # Load Balancer Controller places internal ALBs in subnets with this tag.
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}
