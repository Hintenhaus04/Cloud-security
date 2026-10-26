#!/usr/bin/env bash
# 4.3: eigen keymateriaal (BYOK) genereren met OpenSSL en importeren in AWS KMS.
# Gebruik (in CloudShell, vanuit data-protection/):
#   ./scripts/byok-import.sh "$(terraform output -raw geheim_kms_key_id)"
set -euo pipefail

KEY_ID="${1:?geef de KMS key id mee}"
WORKDIR="$(mktemp -d)"
cd "$WORKDIR"
echo "Werkmap: $WORKDIR"

# 1. Publieke wrapping key en import token ophalen bij KMS (24 uur geldig).
aws kms get-parameters-for-import \
  --key-id "$KEY_ID" \
  --wrapping-algorithm RSAES_OAEP_SHA_256 \
  --wrapping-key-spec RSA_4096 \
  --output json > params.json
python3 -c 'import json,base64,sys; p=json.load(open("params.json")); open("WrappingPublicKey.der","wb").write(base64.b64decode(p["PublicKey"])); open("ImportToken.bin","wb").write(base64.b64decode(p["ImportToken"]))'

# 2. Eigen 256-bit symmetrisch keymateriaal genereren.
openssl rand -out PlaintextKeyMaterial.bin 32

# 3. Keymateriaal versleutelen met de publieke wrapping key van KMS (RSA-OAEP, SHA-256).
openssl pkeyutl -encrypt \
  -in PlaintextKeyMaterial.bin \
  -out EncryptedKeyMaterial.bin \
  -inkey WrappingPublicKey.der -keyform DER -pubin \
  -pkeyopt rsa_padding_mode:oaep \
  -pkeyopt rsa_oaep_md:sha256 \
  -pkeyopt rsa_mgf1_md:sha256

# 4. Versleuteld keymateriaal + import token naar KMS sturen.
aws kms import-key-material \
  --key-id "$KEY_ID" \
  --encrypted-key-material fileb://EncryptedKeyMaterial.bin \
  --import-token fileb://ImportToken.bin \
  --expiration-model KEY_MATERIAL_DOES_NOT_EXPIRE

# 5. Controle: Origin EXTERNAL en KeyState Enabled.
aws kms describe-key --key-id "$KEY_ID" \
  --query 'KeyMetadata.{KeyId:KeyId,Origin:Origin,KeyState:KeyState,ExpirationModel:ExpirationModel}' \
  --output table

echo
echo "Klaar. Bij BYOK beheert SaxIT zelf het origineel van het keymateriaal:"
echo "bewaar $WORKDIR/PlaintextKeyMaterial.bin veilig offline (bijvoorbeeld in een kluis/HSM)"
echo "en verwijder het daarna hier met: shred -u $WORKDIR/PlaintextKeyMaterial.bin"
