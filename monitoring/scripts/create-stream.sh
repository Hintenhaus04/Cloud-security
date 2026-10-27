#!/usr/bin/env bash
# 6.1: centrale Kinesis stream voor de docker logs van web01, web02, app01 en app02.
# Met de AWS CLI in plaats van Terraform: de AWS provider roept altijd IncreaseStreamRetentionPeriod aan,
# en dat weigert het Learner Lab (SCP). De standaard bewaartijd is 24 uur.
# Gebruik: ./scripts/create-stream.sh [stream-naam]
set -euo pipefail

STREAM="${1:-saxit-docker-logs}"

if aws kinesis describe-stream-summary --stream-name "$STREAM" >/dev/null 2>&1; then
  echo "Stream $STREAM bestaat al"
else
  aws kinesis create-stream --stream-name "$STREAM" --shard-count 1 --stream-mode-details StreamMode=PROVISIONED
  echo "Stream $STREAM aangemaakt"
fi
aws kinesis wait stream-exists --stream-name "$STREAM"
aws kinesis add-tags-to-stream --stream-name "$STREAM" --tags Project=SaxIT

# Versleuteling at rest met de AWS managed key voor Kinesis
if [ "$(aws kinesis describe-stream-summary --stream-name "$STREAM" \
        --query StreamDescriptionSummary.EncryptionType --output text)" != "KMS" ]; then
  if aws kinesis start-stream-encryption --stream-name "$STREAM" --encryption-type KMS --key-id alias/aws/kinesis; then
    aws kinesis wait stream-exists --stream-name "$STREAM"
  else
    echo "WAARSCHUWING: encryptie aanzetten geweigerd, de stream werkt wel"
  fi
fi

aws kinesis describe-stream-summary --stream-name "$STREAM" \
  --query 'StreamDescriptionSummary.{Naam:StreamName,Status:StreamStatus,Shards:OpenShardCount,BewaartijdUren:RetentionPeriodHours,Encryptie:EncryptionType}' \
  --output table
