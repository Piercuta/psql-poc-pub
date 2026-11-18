# psql-poc

Aurora PostgreSQL Serverless v2 in isolated subnets on AWS, configured with Terraform from a
CodeBuild-hosted GitHub Actions runner.

## Layout

| Stack | State key | Purpose |
|-------|-----------|---------|
| `terraform/stacks/01-infra` | `psql-poc/dev/terraform.tfstate` | VPC, Aurora, CodeBuild runner, S3 dump archives |
| `terraform/stacks/02-db-config` | `psql-poc/dev/db-config.tfstate` | PostgreSQL content from `config.yaml` |

Modules live in `terraform/modules`. In a production split, the app repo would keep only
`config.yaml`; this stack would be consumed as a versioned module from a platform repo.

## Deployment order

```bash
aws sso login --profile piercuta-dev
export AWS_PROFILE=piercuta-dev

cd terraform/stacks/01-infra && terraform init && terraform apply
```

Stack 02 runs from GitHub Actions (`.github/workflows/terraform-db-config.yml`) on the CodeBuild
runner (Aurora is only reachable from the VPC).

## Schema / database lifecycle

| Status | Meaning | Normal apply |
|--------|---------|--------------|
| `active` | Managed (grants, ownership) | create / update |
| `retired` | Still in the cluster; grants removed | keep object, `prevent_destroy` on |

**Never delete a schema/database line from `config.yaml` on the normal pipeline.** That is blocked
by `prevent_destroy` unless `allow_destroy=true` (destroy workflow only).

### Retire (app change)

1. Set `status: retired` on the schema (and remove mappings that reference it).
2. Merge via the normal `terraform-db-config` workflow.
3. Data remains; apps should already have stopped using it.

### Destroy (platform change)

1. Create a GitHub environment named `destroy` with required reviewers (stricter than `dev`).
2. Run **Actions → Destroy schema → Run workflow** with `database`, `schema`, and `confirm`
   (must equal the schema name). Optional `ticket` for audit metadata.
3. The workflow (after approval on environment `destroy`):
   - refuses if the schema is not `retired`
   - `pg_dump` → S3 (job stops if the dump fails — no drop without archive)
   - `DROP SCHEMA ... CASCADE` via `psql`
   - `terraform state rm` (Terraform forbids variables in `prevent_destroy`, so the
     lifecycle stays `true` forever; destroy is SQL + state rm, not `terraform destroy`)
   - strips the schema from `config.yaml` and opens a sync PR — **merge it immediately**
     so a later normal apply does not recreate an empty schema

Archives land in `s3://<db-archives-bucket>/archives/<env>/<db>/<schema>/<timestamp>/`
(SSE-KMS, versioned, lifecycle expiration from `archive_retention_days`, default 90).

## GitHub Actions workflows

| Workflow | Stacks | Runner |
|----------|--------|--------|
| `terraform-infra.yml` | 01-infra | GitHub-hosted (`ubuntu-latest`) with AWS OIDC |
| `terraform-db-config.yml` | 02-db-config | CodeBuild runner inside the VPC |
| `destroy-schema.yml` | 02-db-config (destroy path) | CodeBuild runner + environment `destroy` |

`terraform-infra.yml` needs repository variables `AWS_PLAN_ROLE_ARN` and `AWS_APPLY_ROLE_ARN`
(OIDC roles; see earlier setup notes).

## Notes

- The runner needs outbound internet (NAT). Aurora subnets stay isolated.
- The CodeBuild GitHub source credential is unique per account and region.
- The runner can read the Aurora master secret: keep the repo private and without fork PRs.
- Configure required reviewers on environments `dev` (normal apply) and `destroy` (drops).
