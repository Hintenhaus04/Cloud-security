###################################################
# 6.1: centrale stream voor de docker logs van web01, web02, app01 en app02
resource "aws_kinesis_stream" "docker_logs" {
  name             = "saxit-docker-logs"
  retention_period = 24
  encryption_type  = "KMS"
  kms_key_id       = "alias/aws/kinesis"

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }
  shard_count = 1
}

output "kinesis_stream_name" {
  value = aws_kinesis_stream.docker_logs.name
}
