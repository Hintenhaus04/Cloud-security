###################################################
# 4.4: mail als er een geheim object wordt gelezen
# CloudTrail data event (GetObject) -> EventBridge rule -> SNS topic -> e-mail
# Geen SSE met de AWS managed SNS key: EventBridge mag daar niet mee publiceren.
resource "aws_sns_topic" "geheim_alert" {
  name = "saxit-geheim-gelezen"
}

data "aws_iam_policy_document" "geheim_alert" {
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.geheim_alert.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "geheim_alert" {
  arn    = aws_sns_topic.geheim_alert.arn
  policy = data.aws_iam_policy_document.geheim_alert.json
}

resource "aws_sns_topic_subscription" "geheim_alert" {
  topic_arn = aws_sns_topic.geheim_alert.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_event_rule" "geheim_gelezen" {
  count       = var.enable_alerting ? 1 : 0
  name        = "saxit-geheim-object-gelezen"
  description = "Geheim object gedownload uit de geheime bucket"
  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["s3.amazonaws.com"]
      eventName   = ["GetObject"]
      requestParameters = {
        bucketName = [aws_s3_bucket.data["geheim"].id]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "geheim_gelezen" {
  count     = var.enable_alerting ? 1 : 0
  rule      = aws_cloudwatch_event_rule.geheim_gelezen[0].name
  target_id = "mail"
  arn       = aws_sns_topic.geheim_alert.arn

  input_transformer {
    input_paths = {
      key  = "$.detail.requestParameters.key"
      user = "$.detail.userIdentity.arn"
      ip   = "$.detail.sourceIPAddress"
      time = "$.detail.eventTime"
    }
    input_template = "\"LET OP: geheim object <key> is gelezen door <user> vanaf <ip> op <time>.\""
  }
}
