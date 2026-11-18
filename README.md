# psql-poc

Aurora PostgreSQL Serverless v2 in isolated subnets on AWS, configured with Terraform from a
CodeBuild-hosted GitHub Actions runner.

## Layout

| Stack | State key | Purpose |
|-------|-----------|---------|
| `terraform/stacks/01-infra` | `psql-poc/dev/terraform.tfstate` | VPC (isolated / private / public subnets, NAT), Aurora cluster, CodeBuild GitHub Actions runner (`cicd.tf`) |
| `terraform/stacks/02-db-config` | `psql-poc/dev/db-config.tfstate` | PostgreSQL provider: databases, schemas, roles, credentials secrets |

Modules live in `terraform/modules`.

## Deployment order

Stack 01 is applied from a workstation with the SSO profile, or from GitHub Actions:

```bash
aws sso login --profile piercuta-dev
export AWS_PROFILE=piercuta-dev   # used by the S3 backend and remote state

cd terraform/stacks/01-infra && terraform init && terraform apply
```

Stack 02 runs from GitHub Actions (`.github/workflows/terraform-db-config.yml`) on the CodeBuild
runner, because the database is only reachable from inside the VPC.

## GitHub Actions workflows

| Workflow | Stacks | Runner |
|----------|--------|--------|
| `terraform-infra.yml` | 01-infra | GitHub-hosted (`ubuntu-latest`) with AWS OIDC |
| `terraform-db-config.yml` | 02-db-config | CodeBuild runner inside the VPC |

`terraform-infra.yml` needs two repository variables holding IAM role ARNs (created manually):

- `AWS_PLAN_ROLE_ARN`: read-only role, plus read access to the state bucket. Trust policy `sub`
  allowed: `repo:Piercuta/psql-poc-pub:pull_request` and `repo:Piercuta/psql-poc-pub:ref:refs/heads/main`.
- `AWS_APPLY_ROLE_ARN`: deployment role (VPC, RDS, IAM, CodeBuild, Secrets Manager, S3 state).
  Trust policy `sub` allowed: `repo:Piercuta/psql-poc-pub:environment:dev` only.

Both trust policies use the GitHub OIDC provider (`token.actions.githubusercontent.com`) with
`aud = sts.amazonaws.com`.

## Notes

- The runner needs outbound internet access (GitHub, Terraform registry): it runs in private
  subnets behind a single NAT Gateway. The Aurora subnets stay fully isolated.
- The CodeBuild GitHub source credential is unique per account and region.
- The runner IAM role can read the Aurora master secret: restrict who can open pull requests
  against this repository (workflows run on the runner for PRs too).
- Configure required reviewers on the GitHub environment `dev` to gate `terraform apply`.
