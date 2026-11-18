# S3 bucket for pg_dump archives taken before a schema/database destroy.
# Written only by the destroy-schema workflow (CodeBuild runner).

resource "aws_s3_bucket" "db_archives" {
  bucket = "${local.name}-db-archives-${local.acct}"

  tags = {
    Name = "${local.name}-db-archives"
  }
}

resource "aws_s3_bucket_public_access_block" "db_archives" {
  bucket = aws_s3_bucket.db_archives.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "db_archives" {
  bucket = aws_s3_bucket.db_archives.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "db_archives" {
  bucket = aws_s3_bucket.db_archives.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "db_archives" {
  bucket = aws_s3_bucket.db_archives.id

  rule {
    id     = "expire-archives"
    status = "Enabled"

    filter {
      prefix = "archives/"
    }

    expiration {
      days = var.archive_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}
