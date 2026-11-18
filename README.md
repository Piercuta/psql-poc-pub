# psql-poc

Aurora PostgreSQL Serverless v2 in isolated subnets on AWS, configured with Terraform from a
CodeBuild-hosted GitHub Actions runner.

## Layout

| Stack | State key | Purpose |
|-------|-----------|---------|
| `terraform/stacks/01-infra` | `psql-poc/dev/terraform.tfstate` | VPC (isolated / private / public subnets, NAT), Aurora cluster |
| `terraform/stacks/02-cicd` | `psql-poc/dev/cicd.tfstate` | CodeBuild GitHub Actions runner in the VPC, IAM role, webhook |
| `terraform/stacks/03-db-config` | `psql-poc/dev/db-config.tfstate` | PostgreSQL provider: databases, schemas, roles, credentials secrets |

Modules live in `terraform/modules`.

## Deployment order

Stacks 01 and 02 are applied from a workstation with the SSO profile:

```bash
aws sso login --profile piercuta-dev
export AWS_PROFILE=piercuta-dev   # used by the S3 backend and remote state

cd terraform/stacks/01-infra && terraform init && terraform apply
cd ../02-cicd               && terraform init && terraform apply
```

Stack 03 runs from GitHub Actions (`.github/workflows/terraform-db-config.yml`) on the CodeBuild
runner, because the database is only reachable from inside the VPC.

## Notes

- The runner needs outbound internet access (GitHub, Terraform registry): it runs in private
  subnets behind a single NAT Gateway. The Aurora subnets stay fully isolated.
- The CodeBuild GitHub source credential is unique per account and region.
- The runner IAM role can read the Aurora master secret: restrict who can open pull requests
  against this repository (workflows run on the runner for PRs too).
- Configure required reviewers on the GitHub environment `dev` to gate `terraform apply`.
