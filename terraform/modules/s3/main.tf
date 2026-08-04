variable "name_prefix" { type = string }
variable "enable_smartstore" { type = bool }
variable "smartstore_retention_days" { type = number }

resource "aws_s3_bucket" "smartstore" {
  count  = var.enable_smartstore ? 1 : 0
  bucket = "${var.name_prefix}-smartstore-${data.aws_caller_identity.current.account_id}"

  tags = { Name = "${var.name_prefix}-smartstore" }
}

resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.name_prefix}-artifacts-${data.aws_caller_identity.current.account_id}"

  tags = { Name = "${var.name_prefix}-artifacts" }
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "smartstore" {
  count  = var.enable_smartstore ? 1 : 0
  bucket = aws_s3_bucket.smartstore[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "smartstore" {
  count  = var.enable_smartstore ? 1 : 0
  bucket = aws_s3_bucket.smartstore[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "smartstore" {
  count  = var.enable_smartstore && var.smartstore_retention_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.smartstore[0].id

  rule {
    id     = "expire-old-buckets"
    status = "Enabled"

    expiration {
      days = var.smartstore_retention_days
    }
  }
}

output "smartstore_bucket_name" {
  value = var.enable_smartstore ? aws_s3_bucket.smartstore[0].id : ""
}

output "smartstore_bucket_arn" {
  value = var.enable_smartstore ? aws_s3_bucket.smartstore[0].arn : ""
}

output "artifacts_bucket_name" {
  value = aws_s3_bucket.artifacts.id
}

output "artifacts_bucket_arn" {
  value = aws_s3_bucket.artifacts.arn
}
