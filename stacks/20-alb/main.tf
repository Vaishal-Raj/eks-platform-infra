locals {
  name = "${var.config.client_id}-${var.config.environment}"
}


# Outputs of stacks/10-network, read from the same client's state bucket
data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "tfstate-${var.config.client_id}-${var.config.environment}-${var.config.account_id}"
    key    = "network/terraform.tfstate"
    region = var.config.region
  }
}

module "alb" {
  source = "git::https://github.com/Vaishal-Raj/eks-platform-modules.git//modules/alb?ref=v0.4.0"

  name                = local.name
  vpc_id              = data.terraform_remote_state.network.outputs.vpc_id
  subnet_ids          = data.terraform_remote_state.network.outputs.private_subnet_ids
  target_egress_cidrs = data.terraform_remote_state.network.outputs.private_subnet_cidrs
  target_port         = var.config.alb.target_port
  deletion_protection = var.config.alb.deletion_protection
}

# - terraform_remote_state reads another stack's outputs, and only its outputs, straight from S3. This is how stacks pass values to each other: 10-network publishes vpc_id, and 20-alb reads it.
# - The bucket name is derived from the config, using the same pattern as backend.hcl, so nothing is hardcoded.
# - The order matters, which is why the folder is 20-: the network state must exist before this stack can read it. The pipeline's sorted loop guarantees that.
# - The plan role can read it: ReadOnlyAccess includes s3:GetObject, so PR plans work.