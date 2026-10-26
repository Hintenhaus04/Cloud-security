# Week 6: Monitoring en logging (praktische opdrachten)

## 6.1 Docker logs centraal naar Kinesis

**Opbouw**

- [`monitoring/kinesis.tf`](../monitoring/kinesis.tf): Kinesis Data Stream `saxit-docker-logs` (1 shard, 24 uur
  bewaartijd, versleuteld met KMS). Eigen map en state, zodat de logs blijven bestaan als de pipeline `infra/` opnieuw
  uitrolt.
- [`infra/templates/kinesis-agent.sh.tftpl`](../infra/templates/kinesis-agent.sh.tftpl) wordt op alle vier de VM's
  uitgevoerd bij het opstarten:
  1. De service `docker-log-export` schrijft de logs van de container (`frontend` of `backend`) naar
     `/var/log/saxit/<container>.log`, met de hostnaam ervoor (bijvoorbeeld `app01 backend 2026-...`). Dat is nodig
     omdat de Kinesis agent geen wildcards in mapnamen ondersteunt, en docker zijn logs opslaat in
     `/var/lib/docker/containers/<id>/`.
  2. De Amazon Kinesis Agent wordt gebouwd vanaf de broncode (er is geen Ubuntu-pakket) en stuurt dat bestand naar
     de stream. Credentials komen van het instance profile `LabInstanceProfile`; er staan dus geen access keys op
     de VM's.

**Uitrollen**

```bash
cd Cloud-security/monitoring
terraform init -backend-config="bucket=$STATE_BUCKET"
terraform apply
```

Rol daarna `infra/` opnieuw uit (pipeline of `terraform apply`), zodat de VM's de agent installeren. Wacht 15 tot
20 minuten: naast de Docker builds wordt nu ook de agent gebouwd.

**Aantonen**

- Op een VM (via de bastion): `sudo service aws-kinesis-agent status` en
  `sudo tail /var/log/aws-kinesis-agent/aws-kinesis-agent.log` (regels met *records sent successfully*).
- Gebruik de applicatie even (producten toevoegen) zodat de backend logregels schrijft.
- **Kinesis > Data streams > saxit-docker-logs > Data viewer**: kies de shard en *Trim horizon*, en maak een
  screenshot van de records. Of in CloudShell: `./monitoring/scripts/read-stream.sh` toont de records van de laatste
  30 minuten, met per regel van welke VM en container hij komt.
- Het tabblad *Monitoring* van de stream (Incoming records / Put records) laat zien dat er data binnenkomt.

**Hoe kan SaxIT dit gebruiken?** Alle logs van alle servers komen op één plek binnen, ook als een VM wordt vervangen
(immutable infrastructure) of wordt aangevallen en de aanvaller lokale logs wist. Vanaf de stream kan SaxIT de logs
doorzetten naar opslag voor audits (Firehose naar S3), realtime analyseren (bijvoorbeeld een Lambda die alarm slaat
bij veel 401/500-fouten of SQL-foutmeldingen), of naar een SIEM sturen. Dat sluit aan op de AVG-eis om
beveiligingsincidenten te kunnen aantonen en onderzoeken.

## 6.4 Security Hub en malware scan

In de console, regio us-east-1:

1. **Security Hub > Go to Security Hub > Enable Security Hub** met de standaarden *AWS Foundational Security Best
   Practices* en *CIS AWS Foundations Benchmark*. Het duurt een paar uur voordat alle controls een resultaat hebben.
2. **GuardDuty > Get started > Enable GuardDuty** (Security Hub haalt de malware-resultaten uit GuardDuty).
3. **GuardDuty > Malware Protection for EC2 > On-demand malware scan**: kies per VM (web01, web02, app01, app02,
   bastion) *Start on-demand scan*, of in CloudShell:

   ```bash
   for id in $(aws ec2 describe-instances --filters "Name=tag:Project,Values=SaxIT" "Name=instance-state-name,Values=running" \
               --query 'Reservations[].Instances[].InstanceId' --output text); do
     aws guardduty start-malware-scan --resource-arn "arn:aws:ec2:us-east-1:$(aws sts get-caller-identity --query Account --output text):instance/$id"
   done
   ```

4. **GuardDuty > Malware scans**: screenshot van de scans met status *Completed* en resultaat (*No threats found*
   of de gevonden malware). Bevindingen verschijnen ook in **Security Hub > Findings**.

Geeft het Learner Lab een `AccessDenied` op GuardDuty of Security Hub, maak dan een screenshot van de foutmelding en
de stappen tot daar.

## 6.5 Logfile-analyse met IsolationForest

Bestanden in [`log-analysis/`](../log-analysis): `log_analysis.py`, de aangeleverde `Linux_2k.log` en de
uitkomsten `inlogpogingen_per_uur.png`, `afwijkende_bronnen.png` en `bronnen_met_score.csv`.

```bash
cd log-analysis
pip install -r requirements.txt
python log_analysis.py
```

**Wat het script doet**

1. *Parsen*: met reguliere expressies haalt het uit iedere regel de dag, het uur, de dienst en het bericht.
   Een inlogpoging is een `authentication failure` (mislukt, met het bron-IP uit `rhost=`) of een
   `session opened` van sshd/login (gelukt). De 909 FTP-regels `connection from` zijn verbindingen, geen
   inlogpogingen, en tellen niet mee.
2. *Tijdlijn per uur*: de datums in de aangeleverde log zijn geanonimiseerd (alles in "Jan", dagen als `00` die niet
   oplopen). De regels staan wel op volgorde, dus het script maakt een nieuw uurblok zodra dag of uur verandert en
   telt per blok de pogingen. Dit is gewone scripting, zonder AI.
3. *Afwijkende uren (AI)*: IsolationForest krijgt per uurblok het aantal pogingen en markeert de uitschieters.
4. *Afwijkende bronnen (AI)*: per bron worden kenmerken berekend: totaal aantal pogingen, maximum in één uur,
   aantal actieve uren, aantal verschillende gebruikersnamen en pogingen per actief uur. IsolationForest bekijkt
   die kenmerken samen en geeft iedere bron een anomaliescore.
5. *Grafieken*: matplotlib tekent beide grafieken met de afwijkingen in rood.

**Resultaat**

- 527 inlogpogingen: 490 mislukt, 37 gelukt.
- Grafiek 1: in een normaal uur zijn er 0 tot ongeveer 20 pogingen. Het uur **Jan 10 16:00** springt eruit met
  **90 pogingen** en is het enige uur dat IsolationForest als afwijkend markeert.
- Grafiek 2: dat komt vrijwel helemaal door **150.183.249.110**, met 80 mislukte pogingen binnen één uur
  (score 0,85). Dat patroon (veel mislukte root-logins in korte tijd vanaf één adres) is een SSH brute-force aanval.
  Ook 207.243.167.114 en n219076184117.netvigator.com worden gemarkeerd (23 pogingen in één uur, score 0,65): kleinere
  aanvallen van hetzelfde type. De andere bronnen doen ongeveer 10 pogingen per uur, het normale gedrag van
  rondscannende bots.

**Waarom IsolationForest?**

- Het is *unsupervised*: je hebt geen gelabelde voorbeelden van aanvallen nodig. Logs zijn bijna nooit gelabeld.
- Het werkt door data willekeurig op te splitsen. Een afwijkend punt (80 pogingen tegen normaal 10) staat apart en is
  na een paar splitsingen al geïsoleerd; normale punten zitten in een grote groep en hebben veel splitsingen nodig.
  Weinig splitsingen = hoge anomaliescore.
- Het kan meerdere kenmerken tegelijk gebruiken (aantal, piek per uur, spreiding) in plaats van één vaste drempel.
- Het is snel en licht genoeg om continu op grote hoeveelheden logs te draaien.

**Gebruikte prompt** (pas aan als je zelf een andere prompt gebruikt hebt):

> Schrijf een Python script dat Linux_2k.log inleest (syslog, met regels van sshd(pam_unix) "authentication failure
> ... rhost=<ip>"). Maak met pandas en matplotlib een grafiek van het aantal inlogpogingen per uur op een tijdlijn, en
> gebruik scikit-learn IsolationForest om afwijkende uren en afwijkende IP-adressen te vinden. Maak een tweede
> grafiek met de IP-adressen die de afwijking veroorzaken. Let op: de datums in de log zijn geanonimiseerd en lopen
> niet op, maar de regels staan wel op volgorde.

**Advies voor SaxIT**: laat dit soort analyse continu meedraaien op de centrale logs uit 6.1 (Kinesis -> Lambda of
een SIEM), en koppel er een actie aan: alert naar het securityteam, en automatisch blokkeren van het IP-adres via een
NACL- of WAF-regel. Voorkom brute force daarnaast aan de bron: SSH alleen via de bastion met keys (zoals nu
ingericht), of nog beter AWS Systems Manager Session Manager zonder open poort 22.
