# Week 4: Data protection (praktische opdrachten 4.2 t/m 4.4)

Alles staat in de map [`data-protection/`](../data-protection). Die map is los van de applicatie-omgeving en heeft
een eigen state (`data-protection/terraform.tfstate` in je state bucket).

| Bestand            | Opdracht | Inhoud                                                                  |
|--------------------|----------|-------------------------------------------------------------------------|
| `buckets.tf`       | 4.2      | Buckets `saxit-openbaar/intern/geheim-<account>`, encryptie, policies   |
| `kms.tf`           | 4.3      | Customer managed key met origin EXTERNAL (BYOK), alias `saxit-geheim-byok` |
| `logging.tf`       | 4.4      | Access logging + CloudTrail data events voor de geheime bucket          |
| `alerting.tf`      | 4.4      | EventBridge rule -> SNS -> e-mail bij `GetObject` op de geheime bucket  |
| `dashboard.tf`     | 4.4      | CloudWatch dashboard `SaxIT-S3-data-protection`                         |
| `scripts/byok-import.sh` | 4.3 | Keymateriaal maken met OpenSSL en importeren in KMS                  |
| `scripts/demo-uploads.sh` | 4.2/4.4 | Toont toegestane en geweigerde uploads, en downloadt het geheime object |

## Uitrollen (CloudShell)

```bash
cd Cloud-security/data-protection
terraform init -backend-config="bucket=$STATE_BUCKET"
terraform apply -var="alert_email=<jouw-mailadres>"
```

Bevestig daarna de mail *AWS Notification - Subscription Confirmation*.

Geeft het Learner Lab een `AccessDenied` op de EventBridge rule, draai dan
`terraform apply -var="alert_email=..." -var="enable_alerting=false"` en laat in je werkstuk
[`alerting.tf`](../data-protection/alerting.tf) zien, plus de rule zoals je hem in de console zou aanmaken
(EventBridge > Rules > Create rule, met het event pattern uit dat bestand en het SNS topic als target).

## 4.2 Buckets, encryptie en policies

- **Encryptie**: `openbaar` en `intern` gebruiken de standaard encryptie SSE-S3 (AES256). `geheim` gebruikt SSE-KMS
  met de BYOK key en een S3 bucket key.
- **Policy per bucket** (zie `aws_iam_policy_document.data`):
  - `DenyInsecureTransport`: alleen HTTPS (encryptie in transit).
  - `DenyUnencryptedUploads` en `DenyWrongEncryptionType`: een upload moet expliciet het juiste encryptietype
    meesturen. Voor `geheim` moet het `aws:kms` zijn én (`DenyOtherKmsKeys`) precies de BYOK key.
  - `DenyWrongClassificationTag`: een object mag alleen in de bucket als het de tag `classificatie=<bucket>` heeft;
    dat geldt ook voor het achteraf aanpassen van tags.
- Alle buckets: Block Public Access, versioning, ACL's uit (BucketOwnerEnforced).

Draai daarna `./scripts/demo-uploads.sh`. Per bucket zie je één geslaagde upload met de juiste tag en encryptie, en
geweigerde uploads zonder tag, met een verkeerde tag, zonder encryptie en (bij geheim) met SSE-S3. Maak een screenshot
van de uitvoer en van de *Properties* (encryptie) en *Tags* van de drie demobestanden in de S3 console.

### Een gebruiker alleen in bepaalde buckets laten uploaden

In het Learner Lab kun je geen IAM users of policies maken, dus dit kun je alleen beschrijven. Je koppelt aan de
gebruiker (of beter aan een groep, bijvoorbeeld `saxit-medewerkers-intern`) een identity-based policy die alleen
`PutObject` op de toegestane bucket toestaat, met dezelfde tag-eis als de bucket:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "UploadAlleenInIntern",
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:PutObjectTagging"],
      "Resource": "arn:aws:s3:::saxit-intern-<account>/*",
      "Condition": {
        "StringEquals": { "s3:RequestObjectTag/classificatie": "intern" }
      }
    },
    {
      "Sid": "BucketsZien",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::saxit-intern-<account>"
    }
  ]
}
```

Omdat IAM standaard alles weigert, kan deze gebruiker nergens anders uploaden. Wil je het ook vanaf de bucketkant
afdwingen, dan voeg je aan de bucket policy van `geheim` een Deny toe met
`"Condition": {"StringNotLike": {"aws:PrincipalArn": ["arn:aws:iam::<account>:role/saxit-geheim-schrijvers"]}}`.
Toegang tot de geheime bucket vereist bovendien `kms:Encrypt`/`kms:Decrypt` op de BYOK key, dus de key policy is een
tweede slot op de deur.

## 4.3 BYOK met eigen keymateriaal

```bash
./scripts/byok-import.sh "$(terraform output -raw geheim_kms_key_id)"
```

Het script:

1. Haalt bij KMS een publieke RSA-4096 *wrapping key* en een *import token* op (`get-parameters-for-import`).
2. Genereert 256 bit keymateriaal met `openssl rand`.
3. Versleutelt dat met de wrapping key (`openssl pkeyutl`, RSAES-OAEP met SHA-256), zodat het materiaal nooit
   onversleuteld naar AWS gaat.
4. Importeert het versleutelde materiaal met het token (`import-key-material`).
5. Laat zien dat de key `Origin: EXTERNAL` en `Enabled` is.

Screenshot voor je werkstuk: **KMS > Customer managed keys > saxit-geheim-byok > Key material**, met
*Origin: External (Import key material)*, zoals in de opdracht.

Draai `byok-import.sh` vóór `demo-uploads.sh`: zolang de key nog in *Pending import* staat, kun je niet naar de
geheime bucket schrijven.

## 4.4 Logging, alert en dashboard

**Logfile met download.** `demo-uploads.sh` downloadt aan het eind `demo-geheim.txt`. Na 5 tot 15 minuten staat dat in
de CloudTrail logs in de log bucket:

```bash
LOGS=$(terraform output -raw log_bucket)
aws s3 cp "s3://$LOGS/AWSLogs/" ./trail --recursive --exclude "*" --include "*CloudTrail/*"
zcat $(find trail -name '*.json.gz') | python3 -c '
import json,sys
for line in sys.stdin:
    for r in json.loads(line)["Records"]:
        if r["eventName"] == "GetObject":
            print(r["eventTime"], r["eventName"], r["requestParameters"]["key"], r["userIdentity"]["arn"], r["sourceIPAddress"])
'
```

De S3 server access logs (`s3://<log_bucket>/s3-access/geheim/`) tonen dezelfde download als `REST.GET.OBJECT`,
maar komen soms pas na een uur binnen. CloudTrail *Event history* in de console laat geen data events zien; daarvoor
moet je echt in de logbestanden kijken.

**E-mail alert.** De EventBridge rule `saxit-geheim-object-gelezen` matcht CloudTrail events met
`eventName = GetObject` op de geheime bucket en stuurt via SNS een mail als
*"LET OP: geheim object demo-geheim.txt is gelezen door ... vanaf ... op ..."*. Screenshot de rule (event pattern
en target) en de ontvangen mail.

**Dashboard.** CloudWatch > Dashboards > `SaxIT-S3-data-protection`: opslag en aantal objecten per classificatie, en
per bucket de GET/PUT requests en 4xx-fouten. De geweigerde uploads uit de demo zie je terug als 4xx-fouten; dat is
nuttig om pogingen tot verkeerd plaatsen van data te herkennen. Opslagmetrics verschijnen pas na ongeveer een dag,
request metrics na ongeveer 15 minuten.

## Opruimen

`terraform destroy` in `data-protection/`. De KMS key gaat dan 7 dagen in *Pending deletion*.

## Nog nodig

Voor 4.1 (classificatie van de dataset) ontbreekt de dataset in de projectbestanden. Lab 5.1 (4.5) doe je zelf in
AWS Academy.
