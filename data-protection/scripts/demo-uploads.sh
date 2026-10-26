#!/usr/bin/env bash
# 4.2 / 4.4: demonstratie van de bucket policies.
# Gebruik (in CloudShell, vanuit data-protection/ na terraform apply en byok-import.sh):
#   ./scripts/demo-uploads.sh
set -uo pipefail

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
KMS_ARN="$(terraform output -raw geheim_kms_key_arn)"
TMP="$(mktemp -d)"

# expect <verwacht: OK|DENIED> <omschrijving> <commando...>
expect() {
  local want="$1" desc="$2"; shift 2
  if out="$("$@" 2>&1)"; then got=OK; else got=DENIED; fi
  if [[ "$got" == "$want" ]]; then mark="[GOED]"; else mark="[ONVERWACHT]"; fi
  printf '%-14s %-8s %s\n' "$mark" "$got" "$desc"
  if [[ "$got" == DENIED ]]; then echo "$out" | tail -n 1 | cut -c1-200 | sed 's/^/               /'; fi
}

for c in openbaar intern geheim; do
  bucket="saxit-$c-$ACCOUNT"
  file="$TMP/demo-$c.txt"
  echo "Demodocument met classificatie $c, aangemaakt $(date -u +%FT%TZ)" > "$file"

  if [[ $c == geheim ]]; then
    enc=(--server-side-encryption aws:kms --ssekms-key-id "$KMS_ARN")
  else
    enc=(--server-side-encryption AES256)
  fi
  wrong_tag=$([[ $c == openbaar ]] && echo intern || echo openbaar)

  echo
  echo "=== Bucket $bucket ==="
  expect OK     "upload met tag classificatie=$c en juiste encryptie" \
    aws s3api put-object --bucket "$bucket" --key "demo-$c.txt" --body "$file" --tagging "classificatie=$c" "${enc[@]}"
  expect DENIED "upload zonder classificatie tag" \
    aws s3api put-object --bucket "$bucket" --key "zonder-tag.txt" --body "$file" "${enc[@]}"
  expect DENIED "upload met verkeerde tag classificatie=$wrong_tag" \
    aws s3api put-object --bucket "$bucket" --key "verkeerde-tag.txt" --body "$file" --tagging "classificatie=$wrong_tag" "${enc[@]}"
  expect DENIED "upload zonder encryptie-header" \
    aws s3api put-object --bucket "$bucket" --key "zonder-encryptie.txt" --body "$file" --tagging "classificatie=$c"
  if [[ $c == geheim ]]; then
    expect DENIED "upload met standaard SSE-S3 i.p.v. de BYOK key" \
      aws s3api put-object --bucket "$bucket" --key "sse-s3.txt" --body "$file" --tagging "classificatie=$c" --server-side-encryption AES256
  fi

  echo "--- Encryptie en tags van het demobestand:"
  aws s3api head-object --bucket "$bucket" --key "demo-$c.txt" \
    --query '{Encryptie:ServerSideEncryption,KmsKey:SSEKMSKeyId,BucketKey:BucketKeyEnabled}' --output table
  aws s3api get-object-tagging --bucket "$bucket" --key "demo-$c.txt" --query TagSet --output table
done

echo
echo "=== 4.4: geheim object downloaden (komt in CloudTrail, access log en triggert de mail) ==="
aws s3api get-object --bucket "saxit-geheim-$ACCOUNT" --key demo-geheim.txt "$TMP/download-geheim.txt" \
  --query '{Encryptie:ServerSideEncryption,KmsKey:SSEKMSKeyId}' --output table
cat "$TMP/download-geheim.txt"
