terraform {
  backend "s3" {
    bucket       = "piercuta-terraform-state"
    key          = "psql-poc/dev/db-config.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}
