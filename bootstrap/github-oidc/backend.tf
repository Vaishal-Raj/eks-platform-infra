terraform {
  backend "s3" {
    bucket       = "tfstate-client-a-dev-264760299713"
    key          = "bootstrap/github-oidc/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}