terraform {
  backend "s3" {
    bucket       = "piercuta-terraform-state"
    key          = "psql-poc/dev/cicd.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}
