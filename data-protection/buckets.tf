data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # Classificatie -> encryptie. Openbaar en intern: standaard SSE-S3, geheim: SSE-KMS met de BYOK key.
  classifications = {
    openbaar = { sse = "AES256" }
    intern   = { sse = "AES256" }
    geheim   = { sse = "aws:kms" }
  }
}

###################################################
# 4.2: een bucket per classificatie
resource "aws_s3_bucket" "data" {
  for_each      = local.classifications
  bucket        = "saxit-${each.key}-${local.account_id}"
  force_destroy = true

  tags = {
    classificatie = each.key
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  for_each                = aws_s3_bucket.data
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "data" {
  for_each = aws_s3_bucket.data
  bucket   = each.value.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "data" {
  for_each = aws_s3_bucket.data
  bucket   = each.value.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  for_each = aws_s3_bucket.data
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.classifications[each.key].sse
      kms_master_key_id = each.key == "geheim" ? aws_kms_external_key.geheim.arn : null
    }
    bucket_key_enabled = each.key == "geheim"
  }
}

###################################################
# 4.2: bucket policies
#  - alleen HTTPS
#  - uploaden alleen met een expliciete encryptie-header van het juiste type (geheim: ook de juiste key)
#  - uploaden en taggen alleen met de tag classificatie=<classificatie van de bucket>
data "aws_iam_policy_document" "data" {
  for_each = aws_s3_bucket.data

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [each.value.arn, "${each.value.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid       = "DenyUnencryptedUploads"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${each.value.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Null"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["true"]
    }
  }

  statement {
    sid       = "DenyWrongEncryptionType"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${each.value.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = [local.classifications[each.key].sse]
    }
  }

  dynamic "statement" {
    for_each = each.key == "geheim" ? [1] : []
    content {
      sid       = "DenyOtherKmsKeys"
      effect    = "Deny"
      actions   = ["s3:PutObject"]
      resources = ["${each.value.arn}/*"]
      principals {
        type        = "*"
        identifiers = ["*"]
      }
      condition {
        test     = "StringNotEquals"
        variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
        values   = [aws_kms_external_key.geheim.arn]
      }
    }
  }

  statement {
    sid       = "DenyWrongClassificationTag"
    effect    = "Deny"
    actions   = ["s3:PutObject", "s3:PutObjectTagging"]
    resources = ["${each.value.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEquals"
      variable = "s3:RequestObjectTag/classificatie"
      values   = [each.key]
    }
  }
}

resource "aws_s3_bucket_policy" "data" {
  for_each   = aws_s3_bucket.data
  bucket     = each.value.id
  policy     = data.aws_iam_policy_document.data[each.key].json
  depends_on = [aws_s3_bucket_public_access_block.data]
}

###################################################
# Request metrics voor het CloudWatch dashboard (4.4)
resource "aws_s3_bucket_metric" "data" {
  for_each = aws_s3_bucket.data
  bucket   = each.value.id
  name     = "EntireBucket"
}
