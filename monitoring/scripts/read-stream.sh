#!/usr/bin/env bash
# 6.1: laat de laatste records uit de Kinesis stream zien.
# Gebruik: ./scripts/read-stream.sh [stream-naam] [minuten-terug]
set -euo pipefail

STREAM="${1:-saxit-docker-logs}"
MINUTES="${2:-30}"
SINCE="$(date -u -d "-$MINUTES minutes" +%s)"

for shard in $(aws kinesis list-shards --stream-name "$STREAM" --query 'Shards[].ShardId' --output text); do
  it="$(aws kinesis get-shard-iterator --stream-name "$STREAM" --shard-id "$shard" \
        --shard-iterator-type AT_TIMESTAMP --timestamp "$SINCE" --query ShardIterator --output text)"
  # Een paar keer doorlezen; een lege batch betekent niet dat de stream leeg is.
  for _ in 1 2 3 4 5; do
    resp="$(aws kinesis get-records --shard-iterator "$it" --limit 200 --output json)"
    echo "$resp" | python3 -c '
import base64, json, sys
for r in json.load(sys.stdin)["Records"]:
    print(base64.b64decode(r["Data"]).decode(errors="replace").rstrip())
'
    it="$(echo "$resp" | python3 -c 'import json,sys; print(json.load(sys.stdin)["NextShardIterator"])')"
  done
done
