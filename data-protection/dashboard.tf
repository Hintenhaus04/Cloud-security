###################################################
# 4.4: CloudWatch dashboard over de buckets.
# Opslagmetrics komen 1x per dag binnen, request metrics na ongeveer 15 minuten.
locals {
  bucket_names = { for k, b in aws_s3_bucket.data : k => b.id }

  storage_metric = { for k, name in local.bucket_names : k => ["AWS/S3", "BucketSizeBytes", "BucketName", name, "StorageType", "StandardStorage", { label = k }] }
  objects_metric = { for k, name in local.bucket_names : k => ["AWS/S3", "NumberOfObjects", "BucketName", name, "StorageType", "AllStorageTypes", { label = k }] }

  request_widget = { for k, name in local.bucket_names : k => {
    type   = "metric"
    width  = 8
    height = 6
    properties = {
      title  = "Requests ${k}"
      region = var.region
      stat   = "Sum"
      period = 300
      view   = "timeSeries"
      metrics = [
        ["AWS/S3", "GetRequests", "BucketName", name, "FilterId", "EntireBucket"],
        [".", "PutRequests", ".", ".", ".", "."],
        [".", "4xxErrors", ".", ".", ".", "."],
      ]
    }
  } }
}

resource "aws_cloudwatch_dashboard" "s3" {
  dashboard_name = "SaxIT-S3-data-protection"
  dashboard_body = jsonencode({
    widgets = concat(
      [
        {
          type   = "metric"
          width  = 12
          height = 6
          properties = {
            title   = "Opslag per classificatie (bytes)"
            region  = var.region
            stat    = "Average"
            period  = 86400
            view    = "timeSeries"
            metrics = values(local.storage_metric)
          }
        },
        {
          type   = "metric"
          width  = 12
          height = 6
          properties = {
            title   = "Aantal objecten per classificatie"
            region  = var.region
            stat    = "Average"
            period  = 86400
            view    = "singleValue"
            metrics = values(local.objects_metric)
          }
        },
      ],
      [for k in keys(local.bucket_names) : local.request_widget[k]],
    )
  })
}
