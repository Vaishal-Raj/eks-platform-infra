#!/usr/bin/env bash

set -euo pipefail

echo "Getting Terraform state bucket name..."

BUCKET_NAME=$(terraform output -raw bucket_name)

echo "Bucket: ${BUCKET_NAME}"

cat > backend.tf <<EOF
terraform {
  backend "s3" {
    bucket       = "${BUCKET_NAME}"
    key          = "bootstrap/state-backend/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
EOF

echo "backend.tf created successfully."

echo "Migrating Terraform state to S3..."

terraform init -migrate-state

echo "Terraform state successfully migrated to S3."

echo ""
echo "=== Verification 1: Terraform State ==="
terraform state list

echo ""
echo "=== Verification 2: Terraform Plan ==="
terraform plan

echo ""
echo "=== Verification 3: S3 State ==="
aws s3 ls "s3://${BUCKET_NAME}" --recursive

echo ""
echo "All verification steps completed successfully."

echo "Removing local Terraform state..."

rm -f terraform.tfstate terraform.tfstate.backup

echo "Local Terraform state removed."
echo "Terraform is now using S3 remote state."