###################################################
# 4.3: customer managed key met eigen (BYOK) keymateriaal.
# Terraform maakt de key aan zonder materiaal (status PendingImport);
# scripts/byok-import.sh genereert het materiaal met OpenSSL en importeert het.
resource "aws_kms_external_key" "geheim" {
  description             = "SaxIT BYOK key voor de bucket met geheime documenten"
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "geheim" {
  name          = "alias/saxit-geheim-byok"
  target_key_id = aws_kms_external_key.geheim.id
}
