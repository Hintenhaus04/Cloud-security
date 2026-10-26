# Omgeving herbouwen in het AWS Learner Lab

Dit stappenplan zet de SaxIT 3-tier omgeving opnieuw neer, inclusief de bastion host (opdracht 1.3) en de
aangescherpte security groups uit week 3. Het volgt de handleiding *Cloud Sec module launch begin environment*,
maar met de Terraform-bestanden uit deze repository.

| Map         | Wat                                                        | Hoe uitrollen                      |
|-------------|------------------------------------------------------------|------------------------------------|
| `database/` | DB VPC, subnets, RDS MySQL (`cloudsecdb`)                  | Eén keer handmatig vanuit CloudShell |
| `infra/`    | App VPC, NAT, peering, bastion, 4 VM's, 2 load balancers   | Eerste keer CloudShell, daarna GitHub Actions |

Houd net als in de handleiding een `labnotes.txt` bij met de waarden die je onderweg krijgt.

## 1. Voorbereiding in de console (regio us-east-1)

1. Start het Learner Lab en open de AWS console.
2. **EC2 > Key pairs > Create key pair**, type RSA, formaat `.pem`. Noteer de naam (bijvoorbeeld `key1`) en bewaar de
   `.pem` op je laptop.
3. **S3 > Create bucket** voor de Terraform state. Laat *Block all public access* aan en zet *Bucket Versioning* aan.
   Noteer de bucketnaam.
4. Zoek het publieke IP-adres van je laptop op (open <https://checkip.amazonaws.com> in je browser). Alleen dit adres
   mag straks naar de bastion host SSH'en. Let op: dit is níet het IP van CloudShell.

## 2. Terraform in CloudShell

Open CloudShell en installeer Terraform zoals in de handleiding:

```bash
git clone https://github.com/tfutils/tfenv.git ~/.tfenv
mkdir -p ~/bin && ln -s ~/.tfenv/bin/* ~/bin/
tfenv install 1.11.2 && tfenv use 1.11.2
terraform --version
```

Haal de repository binnen (bij een private repo: maak een GitHub personal access token en gebruik die als wachtwoord,
of upload de mappen via *Actions > Upload file*):

```bash
git clone https://github.com/Hintenhaus04/Cloud-security.git
cd Cloud-security
```

Zet de waarden die beide mappen nodig hebben in je shell:

```bash
export STATE_BUCKET=<naam-van-je-state-bucket>
export TF_VAR_db_password='<kies-een-sterk-wachtwoord>'   # zelfde wachtwoord gebruik je straks in GitHub
export TF_VAR_key_name=key1
export TF_VAR_admin_cidr=<ip-van-je-laptop>/32
```

## 3. Database uitrollen (`database/`)

```bash
cd database
terraform init -backend-config="bucket=$STATE_BUCKET"
terraform apply
```

Dit duurt ongeveer 10 minuten. Noteer de output `db_endpoint` in je labnotes.

De handleiding laat je hierna de state verwijderen zodat een `terraform destroy` de database niet kan weggooien. Dat
is hier niet nodig: de database heeft een eigen state-bestand (`database/terraform.tfstate` in de bucket), de pipeline
raakt die map nooit aan, en `prevent_destroy` blokkeert een destroy.

## 4. Applicatie-omgeving uitrollen (`infra/`)

```bash
cd ../infra
terraform init -backend-config="bucket=$STATE_BUCKET"
terraform apply
```

Terraform zoekt de database VPC, de route table en het RDS endpoint zelf op, dus je hoeft geen ID's meer in het
script aan te passen. Wacht daarna minstens 10 tot 15 minuten: de VM's bouwen bij het opstarten de Docker images
(op een t2.micro duurt vooral de React build even).

Controleer daarna:

- **EC2 > Load Balancers > presentation-lb / application-lb > Resource map**: alle targets *Healthy*.
- Open de output `presentation_lb_url` in je browser. De productenlijst moet laden en je moet producten kunnen
  toevoegen; dat bewijst de hele keten web -> app -> database.

## 5. Inloggen via de bastion host

Alle VM's zijn alleen via de bastion bereikbaar. Gebruik ProxyJump, zodat je private key op je laptop blijft:

```bash
chmod 400 key1.pem
ssh-add key1.pem
ssh -J ubuntu@<bastion_public_ip> ubuntu@<prive-ip-van-web01-of-app01>
```

De IP-adressen staan in de outputs `bastion_public_ip`, `web_private_ips` en `app_private_ips`
(`terraform output` toont ze opnieuw). Op Windows werkt dit in PowerShell met de ingebouwde OpenSSH; start dan eerst
de service *OpenSSH Authentication Agent*.

Gaat de applicatie niet werken, kijk dan op de VM in `/var/log/user-data.log` en met `sudo docker ps -a` /
`sudo docker logs <id>`.

## 6. Pipeline koppelen (opdracht 3.3)

Zie [week 3](week3-infrastructure-protection.md#33-immutable-infrastructure-met-github-actions).

## Opruimen of nieuwe lab-sessie

- Het Learner Lab stopt na de sessie de VM's, maar laat alles staan. Na een herstart krijgen de VM's andere
  publieke IP's; draai dan gewoon de pipeline opnieuw (of `terraform apply` in `infra/`).
- Wil je kosten sparen: `terraform destroy` in `infra/`. De NAT gateway kost ongeveer $1 per dag.
