# Week 4.1: Dataclassificatie SaxIT

De opdracht verwijst naar een "gegeven dataset", maar die was niet beschikbaar. Daarom is een fictieve, realistische
SaxIT-dataset gemaakt: [`data-protection/dataset/saxit_dataset.xlsx`](../data-protection/dataset/saxit_dataset.xlsx)
(opnieuw te maken met `maak_dataset.py`). De dataset bevat:

- **Data-inventaris**: 24 soorten data die SaxIT opslaat, met eigenaar, systeem, persoonsgegevens, volume en
  bewaartermijn.
- **Voorbeeldrecords** uit de productiedatabase: klanten (contactpersonen, IBAN, prijsafspraken), CMDB-items van
  klanten (hostnamen, IP-adressen, softwareversies) en API-sleutels.

## Werkwijze

Ieder data-element is beoordeeld op vier vragen:

1. **Impact bij een lek**: wat is de schade voor klanten, medewerkers of SaxIT als dit op straat ligt?
2. **Persoonsgegevens**: valt het onder de AVG, en zo ja, gaat het om gewone of bijzondere gegevens (BSN, gezondheid)?
3. **Misbruikwaarde**: helpt de data een aanvaller verder (sleutels, IP's, kwetsbaarheden)?
4. **Wie mag erbij**: iedereen, alle medewerkers, of alleen een kleine groep met een functionele reden?

Het hoogste antwoord bepaalt de classificatie. Data die anders gelabeld wordt, krijgt dus nooit minder bescherming
dan het gevoeligste deel ervan (een back-up met klantgegevens is net zo geheim als de klantgegevens zelf).

## De drie categorieën

| Categorie   | Definitie                                                                                              | Schade bij lek |
|-------------|--------------------------------------------------------------------------------------------------------|----------------|
| **Openbaar** | Bedoeld voor publicatie. Iedereen mag het zien.                                                       | Geen |
| **Intern**   | Voor alle medewerkers van SaxIT. Niet bedoeld voor buiten, maar een lek geeft beperkte schade.        | Beperkt: imago, kleine voorsprong voor concurrent of aanvaller |
| **Geheim**   | Alleen voor een kleine groep met een functionele reden. Bevat persoonsgegevens, klantdata, sleutels of aanvalsinformatie. | Groot: AVG-boete, meldplicht, aansprakelijkheid, overname van systemen |

## Classificatie van de dataset

### Openbaar

| ID  | Data-element | Motivatie |
|-----|--------------|-----------|
| D01 | Productbrochure CMDB | Marketingmateriaal, juist gemaakt om te verspreiden. |
| D02 | Prijslijst abonnementen | Staat op de website. De afwijkende prijsafspraken per klant (D14) zijn wél geheim. |
| D03 | Publieke API-documentatie | Klanten moeten de API kunnen gebruiken. Bevat geen sleutels of interne endpoints. |
| D04 | Persberichten en blogs | Gepubliceerd nieuws. |
| D05 | Algemene voorwaarden en privacyverklaring | Wettelijk verplicht om openbaar te maken (AVG art. 13). |
| D06 | Statuspagina beschikbaarheid | Transparantie naar klanten. Toont alleen of de dienst werkt, niet hoe. |

### Intern

| ID  | Data-element | Motivatie |
|-----|--------------|-----------|
| D07 | Werkinstructies en runbooks | Nodig voor alle beheerders. Geeft inzicht in werkwijze, maar geen toegang. Runbooks mogen geen wachtwoorden bevatten; staat er toch een in, dan wordt het document geheim. |
| D08 | Architectuurplaten (high level) | Helpt medewerkers het systeem te begrijpen. Zonder IP's, poorten en sleutels is de misbruikwaarde beperkt. |
| D09 | Organigram en zakelijke contactgegevens | Persoonsgegevens, maar zakelijk en binnen de organisatie normaal om te delen. Naar buiten toe zou het phishing makkelijker maken, dus niet openbaar. |
| D10 | Projectplanningen en notulen | Bedrijfsvertrouwelijk (roadmap), een lek geeft concurrentievoordeel maar geen directe schade. |
| D11 | Infrastructure-as-code (zonder secrets) | Ontwikkelaars werken er samen in. Secrets staan in GitHub Secrets / Secrets Manager, niet in de code. |
| D12 | Geanonimiseerde gebruiksstatistieken | Niet herleidbaar naar personen, dus geen persoonsgegevens; wel bedrijfsgevoelig (groeicijfers). |

### Geheim

| ID  | Data-element | Motivatie |
|-----|--------------|-----------|
| D13 | Klantgegevens (contactpersonen) | Persoonsgegevens (naam, e-mail, telefoon) van 1.200 klanten. Lek = meldplicht bij de AP en kans op boete. |
| D14 | Contracten en prijsafspraken | Bedrijfsgevoelig (kortingen) en bevat namen en handtekeningen. |
| D15 | Facturen en betaalgegevens | IBAN plus naam maakt fraude en phishing mogelijk. Fiscale bewaarplicht van 7 jaar. |
| D16 | CMDB-inhoud van klanten | Het kernproduct. Een overzicht van servers, IP's en verouderde versies ("End-of-life", "Patch achterstand") is een kant-en-klaar aanvalsplan voor de klant. SaxIT is hier verwerker; de klant is eigenaar. |
| D17 | API-sleutels en service-accounts | Wie de sleutel heeft, is de klant. Een `admin`-sleutel geeft volledige toegang tot de CMDB van die klant. |
| D18 | Wachtwoordhashes eindgebruikers | Inloggegevens; hashes kunnen offline gekraakt worden. |
| D19 | Personeelsdossiers | BSN, salaris en verzuim. BSN en gezondheid zijn de zwaarst beschermde gegevens onder de AVG (art. 9 en art. 87 / UAVG). |
| D20 | Pentestrapporten en kwetsbaarheden | Beschrijft precies hoe SaxIT binnen te komen is, zolang de bevindingen niet zijn opgelost. |
| D21 | Audit- en toegangslogs | Bevatten IP-adressen en gebruikers-ID's (persoonsgegevens) en zijn bewijsmateriaal bij incidenten; ze mogen niet aangepast kunnen worden. |
| D22 | Databaseback-ups | Bevatten alles uit D13, D16 en D18 en zijn daarom minstens zo geheim. |
| D23 | Encryptiesleutels (keymateriaal) | Met het keymateriaal is alle geheime data te ontsleutelen. Het hoogste beschermingsniveau binnen geheim. |
| D24 | Supporttickets | Klanten plakken er screenshots, foutmeldingen en soms wachtwoorden in. Omdat de inhoud niet te voorspellen is, wordt alles als geheim behandeld. |

Verdeling: **6 openbaar, 6 intern, 12 geheim**. Dat de helft geheim is, past bij een SaaS-CMDB: het product bestaat
uit gevoelige klantdata.

## Maatregelen per categorie

| Maatregel | Openbaar | Intern | Geheim |
|-----------|----------|--------|--------|
| **Encryptie at rest** | SSE-S3 (standaard). Niet strikt nodig, maar het kost niets. | SSE-S3 (AES-256, sleutel beheerd door AWS). | SSE-KMS met een **customer managed key met eigen keymateriaal (BYOK)**. SaxIT bepaalt zelf wie de sleutel mag gebruiken en kan hem intrekken. RDS en back-ups versleuteld met KMS. |
| **Encryptie in transit** | HTTPS (TLS 1.2+) voor integriteit, zodat niemand de inhoud onderweg aanpast. | Verplicht HTTPS (bucket policy `aws:SecureTransport`). | Verplicht HTTPS en TLS naar RDS. Bucket policy weigert uploads zonder de juiste KMS-sleutel. |
| **Toegangsbeheer (IAM)** | Lezen voor iedereen via de website/CDN; schrijven alleen voor Marketing via een rol. | Alleen medewerkers via SSO (Entra ID gekoppeld aan IAM Identity Center); lezen voor alle medewerkers, schrijven per afdeling. Geen publieke toegang (Block Public Access). | Least privilege: alleen een benoemde rol per data-element (bijv. `saxit-finance` voor D15). MFA verplicht, tijdelijke rechten (just-in-time) voor beheerders, key policy op de KMS-sleutel als tweede slot. Multi-tenant: elke klant ziet alleen eigen CMDB-data (tenant-ID in iedere query, getest). |
| **Logging en monitoring** | Alleen beschikbaarheid en wijzigingen (wie heeft de website aangepast). | CloudTrail management events, S3 server access logs. Alarm bij het publiek maken van een bucket (AWS Config-regel). | CloudTrail **data events** op ieder lees- en schrijfverzoek, logs onveranderbaar opgeslagen (log file validation, aparte log-bucket). EventBridge-alert bij het lezen van geheime objecten, GuardDuty voor afwijkend gedrag. |
| **Data Loss Prevention (DLP)** | Controle vóór publicatie dat er geen interne of geheime data in een document staat. | Amazon Macie scant periodiek op persoonsgegevens die per ongeluk in interne buckets terechtkomen. E-mail-DLP waarschuwt bij versturen naar buiten. | Macie continu op geheime buckets; blokkeren van extern delen; uploads alleen met de tag `classificatie=geheim`; geen download naar privé-apparaten; secret scanning in GitHub voor D17. |
| **Bewaren en verwijderen** | Tot vervanging. | Volgens bewaartermijn in de inventaris. | Strikt volgens bewaartermijn (AVG-dataminimalisatie). S3 Lifecycle-regels verwijderen automatisch; versioning en Object Lock voor logs en back-ups. |

## Koppeling met de praktijk (4.2 t/m 4.4)

Per classificatie is een bucket ingericht (`saxit-openbaar-…`, `saxit-intern-…`, `saxit-geheim-…`). De bucket policies
dwingen af dat alleen data met de juiste tag `classificatie` in de bijbehorende bucket komt en dat de juiste encryptie
wordt gebruikt. De geheime bucket gebruikt de BYOK-sleutel, heeft CloudTrail data events en stuurt een mail zodra een
geheim object wordt gelezen. Zie [week4-data-protection.md](week4-data-protection.md).

De demobestanden in `scripts/demo-uploads.sh` zijn gebaseerd op deze dataset: de prijslijst (D02) is openbaar, een
runbook (D07) is intern en een klantexport (D13) is geheim.
