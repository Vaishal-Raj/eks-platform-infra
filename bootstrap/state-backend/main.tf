provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "poc-gvr"
      Client      = var.client_id
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}


# default_tags adds these tags to every resource automatically.
# - A data block reads something that already exists instead of creating it. Here it reads your account ID.
# - Bucket names must be unique across all AWS customers worldwide. Adding your account ID makes a collision practically impossible.

locals {
  bucket_name = "tfstate-${var.client_id}-${var.environment}-${data.aws_caller_identity.current.account_id}"
}


resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name
  #   force_destroy = true # temporary: lets Terraform delete all object versions
  lifecycle {
    prevent_destroy = true
  }
}

# prevent_destroy makes Terraform refuse to delete this bucket, even if you run terraform destroy. Losing the state bucket means Terraform forgets everything it built.


resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}


# - Every time state is saved, S3 keeps the old copy. If state gets corrupted, you can roll back.
# - Notice aws_s3_bucket.state.id: that's how one resource references another. The reference also tells Terraform to create the bucket first.

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# - State files often contain secrets (database endpoints, sometimes passwords), so they're encrypted with KMS. Leaving out a key ID means AWS uses its built-in aws/s3 key. Your own KMS key can come later.
# - bucket_key_enabled cuts down KMS calls, which keeps the cost low.
# - The public access block has four switches, all on. This bucket can never be made public, even by mistake.



# Writes the backend settings for this client-env, so no one types the bucket name.
# resource "local_file" "backend_config" {
#   filename        = "${path.module}/../../backends/${var.client_id}-${var.environment}.s3.tfbackend"
#   file_permission = "0644"

#   content = <<-EOT
#     bucket       = "${aws_s3_bucket.state.id}"
#     region       = "${var.region}"
#     encrypt      = true
#     use_lockfile = true
#   EOT
# }

# - path.module is the folder this file lives in. ../../backends/ resolves to infra-repo/backends/.
# - .tfbackend is the file extension Terraform recommends for backend settings.
# - There's no key in it on purpose. Every root (bootstrap, network, and later database) shares the bucket but passes its own key.
# - Because it's built from aws_s3_bucket.state.id, the name always matches the real bucket.