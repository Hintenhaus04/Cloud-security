output "buckets" {
  value = local.bucket_names
}

output "geheim_kms_key_id" {
  value = aws_kms_external_key.geheim.id
}

output "geheim_kms_key_arn" {
  value = aws_kms_external_key.geheim.arn
}

output "log_bucket" {
  value = aws_s3_bucket.logs.id
}
