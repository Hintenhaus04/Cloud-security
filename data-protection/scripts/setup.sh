#!/usr/bin/env bash
# Week 4.2 t/m 4.4: buckets per classificatie, BYOK KMS key, logging, alert en dashboard.
#
# Dit is een AWS CLI-script in plaats van Terraform: de Terraform AWS provider leest bij iedere
# bucket de object lock configuratie uit, en dat blokkeert het Learner Lab (service control policy).
# Het script is idempotent: je kunt het opnieuw draaien, bestaande resources worden hergebruikt.
#
# Gebruik (CloudShell):  ./scripts/setup.sh <jouw-mailadres>
set -uo pipefail

ALERT_EMAIL="${1:?gebruik: ./scripts/setup.sh <mailadres voor de alert>}"
REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$REGION"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
LOGS="saxit-logs-$ACCOUNT"
ALIAS="alias/saxit-geheim-byok"
TRAIL="saxit-geheim-data-events"
TOPIC_NAME="saxit-geheim-gelezen"
RULE="saxit-geheim-object-gelezen"
DASHBOARD="SaxIT-S3-data-protection"
CLASSES=(openbaar intern geheim)

step() { echo; echo "=== $*"; }
ok()   { echo "    OK: $*"; }
warn() { echo "    LET OP: $*"; }

###################################################
step "4.3 KMS key met eigen keymateriaal (origin EXTERNAL)"
KEY_ID="$(aws kms describe-key --key-id "$ALIAS" --query KeyMetadata.KeyId --output text 2>/dev/null || true)"
if [[ -z "$KEY_ID" || "$KEY_ID" == "None" ]]; then
  KEY_ID="$(aws kms create-key --origin EXTERNAL \
    --description "SaxIT BYOK key voor de bucket met geheime documenten" \
    --tags TagKey=Project,TagValue=SaxIT \
    --query KeyMetadata.KeyId --output text)"
  aws kms create-alias --alias-name "$ALIAS" --target-key-id "$KEY_ID"
  ok "key $KEY_ID aangemaakt (status PendingImport, draai daarna byok-import.sh)"
else
  ok "bestaande key $KEY_ID hergebruikt"
fi
KEY_ARN="$(aws kms describe-key --key-id "$KEY_ID" --query KeyMetadata.Arn --output text)"

###################################################
make_bucket() {
  local b="$1"
  if aws s3api head-bucket --bucket "$b" 2>/dev/null; then
    ok "bucket $b bestaat al"
  else
    aws s3api create-bucket --bucket "$b" >/dev/null && ok "bucket $b aangemaakt"
  fi
  aws s3api put-public-access-block --bucket "$b" --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  aws s3api put-bucket-ownership-controls --bucket "$b" \
    --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'
}

# Bucket policy per classificatie:
#  - alleen HTTPS
#  - uploads alleen met een expliciete encryptie-header van het juiste type (geheim: ook de juiste key)
#  - uploads en tags alleen met classificatie=<classificatie van de bucket>
bucket_policy() {
  local c="$1" arn="arn:aws:s3:::saxit-$1-$ACCOUNT" sse="AES256" kms_statement=""
  if [[ $c == geheim ]]; then
    sse="aws:kms"
    kms_statement='{"Sid":"DenyOtherKmsKeys","Effect":"Deny","Principal":"*","Action":"s3:PutObject","Resource":"'"$arn"'/*","Condition":{"StringNotEquals":{"s3:x-amz-server-side-encryption-aws-kms-key-id":"'"$KEY_ARN"'"}}},'
  fi
  cat <<EOF
{"Version":"2012-10-17","Statement":[
{"Sid":"DenyInsecureTransport","Effect":"Deny","Principal":"*","Action":"s3:*","Resource":["$arn","$arn/*"],"Condition":{"Bool":{"aws:SecureTransport":"false"}}},
{"Sid":"DenyUnencryptedUploads","Effect":"Deny","Principal":"*","Action":"s3:PutObject","Resource":"$arn/*","Condition":{"Null":{"s3:x-amz-server-side-encryption":"true"}}},
{"Sid":"DenyWrongEncryptionType","Effect":"Deny","Principal":"*","Action":"s3:PutObject","Resource":"$arn/*","Condition":{"StringNotEquals":{"s3:x-amz-server-side-encryption":"$sse"}}},
$kms_statement
{"Sid":"DenyWrongClassificationTag","Effect":"Deny","Principal":"*","Action":["s3:PutObject","s3:PutObjectTagging"],"Resource":"$arn/*","Condition":{"StringNotEquals":{"s3:RequestObjectTag/classificatie":"$c"}}}
]}
EOF
}

bucket_encryption() {
  if [[ $1 == geheim ]]; then
    echo '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms","KMSMasterKeyID":"'"$KEY_ARN"'"},"BucketKeyEnabled":true}]}'
  else
    echo '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
  fi
}

step "4.2 Buckets per classificatie"
for c in "${CLASSES[@]}"; do
  b="saxit-$c-$ACCOUNT"
  make_bucket "$b"
  aws s3api put-bucket-tagging --bucket "$b" --tagging "TagSet=[{Key=classificatie,Value=$c},{Key=Project,Value=SaxIT}]"
  aws s3api put-bucket-versioning --bucket "$b" --versioning-configuration Status=Enabled
  aws s3api put-bucket-encryption --bucket "$b" --server-side-encryption-configuration "$(bucket_encryption "$c")"
  aws s3api put-bucket-policy --bucket "$b" --policy "$(bucket_policy "$c")" && ok "policy op $b"
  # Request metrics voor het dashboard
  aws s3api put-bucket-metrics-configuration --bucket "$b" --id EntireBucket \
    --metrics-configuration '{"Id":"EntireBucket"}'
done

###################################################
step "4.4 Log bucket, access logging en CloudTrail data events"
make_bucket "$LOGS"
aws s3api put-bucket-encryption --bucket "$LOGS" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-bucket-policy --bucket "$LOGS" --policy "$(cat <<EOF
{"Version":"2012-10-17","Statement":[
{"Sid":"S3ServerAccessLogs","Effect":"Allow","Principal":{"Service":"logging.s3.amazonaws.com"},"Action":"s3:PutObject","Resource":"arn:aws:s3:::$LOGS/s3-access/*","Condition":{"StringEquals":{"aws:SourceAccount":"$ACCOUNT"}}},
{"Sid":"CloudTrailAclCheck","Effect":"Allow","Principal":{"Service":"cloudtrail.amazonaws.com"},"Action":"s3:GetBucketAcl","Resource":"arn:aws:s3:::$LOGS"},
{"Sid":"CloudTrailWrite","Effect":"Allow","Principal":{"Service":"cloudtrail.amazonaws.com"},"Action":"s3:PutObject","Resource":"arn:aws:s3:::$LOGS/AWSLogs/$ACCOUNT/*","Condition":{"StringEquals":{"s3:x-amz-acl":"bucket-owner-full-control"}}}
]}
EOF
)" && ok "policy op $LOGS"

aws s3api put-bucket-logging --bucket "saxit-geheim-$ACCOUNT" --bucket-logging-status \
  '{"LoggingEnabled":{"TargetBucket":"'"$LOGS"'","TargetPrefix":"s3-access/geheim/"}}' && ok "access logging aan op geheim"

if aws cloudtrail get-trail --name "$TRAIL" >/dev/null 2>&1; then
  ok "trail $TRAIL bestaat al"
else
  aws cloudtrail create-trail --name "$TRAIL" --s3-bucket-name "$LOGS" \
    --no-include-global-service-events --enable-log-file-validation >/dev/null && ok "trail $TRAIL aangemaakt"
fi
aws cloudtrail put-event-selectors --trail-name "$TRAIL" --event-selectors \
  '[{"ReadWriteType":"All","IncludeManagementEvents":false,"DataResources":[{"Type":"AWS::S3::Object","Values":["arn:aws:s3:::saxit-geheim-'"$ACCOUNT"'/"]}]}]' >/dev/null \
  && ok "data events voor de geheime bucket"
aws cloudtrail start-logging --name "$TRAIL" && ok "trail logt"

###################################################
step "4.4 Alert: CloudTrail -> EventBridge -> SNS -> e-mail"
# Geen SSE met de AWS managed SNS key: EventBridge mag daar niet mee publiceren.
TOPIC_ARN="$(aws sns create-topic --name "$TOPIC_NAME" --query TopicArn --output text)"
aws sns set-topic-attributes --topic-arn "$TOPIC_ARN" --attribute-name Policy --attribute-value \
  '{"Version":"2012-10-17","Statement":[{"Sid":"EventBridgePublish","Effect":"Allow","Principal":{"Service":"events.amazonaws.com"},"Action":"sns:Publish","Resource":"'"$TOPIC_ARN"'"}]}'
if aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" --query 'Subscriptions[].Endpoint' --output text | grep -qw "$ALERT_EMAIL"; then
  ok "$ALERT_EMAIL is al geabonneerd"
else
  aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email --notification-endpoint "$ALERT_EMAIL" >/dev/null
  ok "bevestigingsmail gestuurd naar $ALERT_EMAIL"
fi

EVENT_PATTERN='{"source":["aws.s3"],"detail-type":["AWS API Call via CloudTrail"],"detail":{"eventSource":["s3.amazonaws.com"],"eventName":["GetObject"],"requestParameters":{"bucketName":["saxit-geheim-'"$ACCOUNT"'"]}}}'
if aws events put-rule --name "$RULE" --event-pattern "$EVENT_PATTERN" \
     --description "Geheim object gedownload uit de geheime bucket" >/dev/null; then
  aws events put-targets --rule "$RULE" --targets '[{"Id":"mail","Arn":"'"$TOPIC_ARN"'","InputTransformer":{"InputPathsMap":{"key":"$.detail.requestParameters.key","user":"$.detail.userIdentity.arn","ip":"$.detail.sourceIPAddress","time":"$.detail.eventTime"},"InputTemplate":"\"LET OP: geheim object <key> is gelezen door <user> vanaf <ip> op <time>.\""}}]' >/dev/null \
    && ok "EventBridge rule $RULE met SNS target"
else
  warn "EventBridge rule geweigerd door het Learner Lab. Laat in je verslag het event pattern zien:"
  echo "$EVENT_PATTERN"
fi

###################################################
step "4.4 CloudWatch dashboard"
storage=""; objects=""; requests=""
for c in "${CLASSES[@]}"; do
  b="saxit-$c-$ACCOUNT"
  storage+='["AWS/S3","BucketSizeBytes","BucketName","'"$b"'","StorageType","StandardStorage",{"label":"'"$c"'"}],'
  objects+='["AWS/S3","NumberOfObjects","BucketName","'"$b"'","StorageType","AllStorageTypes",{"label":"'"$c"'"}],'
  requests+='{"type":"metric","width":8,"height":6,"properties":{"title":"Requests '"$c"'","region":"'"$REGION"'","stat":"Sum","period":300,"view":"timeSeries","metrics":[["AWS/S3","GetRequests","BucketName","'"$b"'","FilterId","EntireBucket"],[".","PutRequests",".",".",".","."],[".","4xxErrors",".",".",".","."]]}},'
done
DASHBOARD_BODY='{"widgets":[
{"type":"metric","width":12,"height":6,"properties":{"title":"Opslag per classificatie (bytes)","region":"'"$REGION"'","stat":"Average","period":86400,"view":"timeSeries","metrics":['"${storage%,}"']}},
{"type":"metric","width":12,"height":6,"properties":{"title":"Aantal objecten per classificatie","region":"'"$REGION"'","stat":"Average","period":86400,"view":"singleValue","metrics":['"${objects%,}"']}},
'"${requests%,}"'
]}'
aws cloudwatch put-dashboard --dashboard-name "$DASHBOARD" --dashboard-body "$DASHBOARD_BODY" >/dev/null && ok "dashboard $DASHBOARD"

###################################################
step "Klaar"
cat <<EOF
    Buckets:    saxit-openbaar-$ACCOUNT, saxit-intern-$ACCOUNT, saxit-geheim-$ACCOUNT
    Logs:       $LOGS
    KMS key:    $KEY_ARN ($ALIAS)
    Volgende stappen:
      1. Bevestig de mail van AWS Notifications.
      2. ./scripts/byok-import.sh
      3. ./scripts/demo-uploads.sh
EOF
