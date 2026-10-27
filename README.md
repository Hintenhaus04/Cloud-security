# Cloud Security: SaxIT

Terraform en uitwerkingen van de praktische opdrachten voor de module Cloud Security (casus SaxIT), uitgerold in
het AWS Learner Lab.

| Map / bestand                        | Inhoud                                                        |
|--------------------------------------|---------------------------------------------------------------|
| `database/`                          | DB VPC en RDS MySQL; één keer handmatig uitrollen              |
| `infra/`                             | 3-tier applicatie-omgeving met bastion host                    |
| `.github/workflows/infra.yml`        | Pipeline: validate, en op `main` destroy + apply van `infra/`  |
| `docs/01-omgeving-herbouwen.md`      | Stappenplan om de omgeving opnieuw neer te zetten              |
| `docs/week3-infrastructure-protection.md` | Uitwerking opdracht 3.1 t/m 3.3                           |
| `data-protection/`                   | AWS CLI-scripts: S3 buckets per classificatie, BYOK KMS key, logging en alerts (week 4) |
| `docs/week4-1-dataclassificatie.md`  | Uitwerking opdracht 4.1, met dataset in `data-protection/dataset/` |
| `docs/week4-data-protection.md`      | Uitwerking opdracht 4.2 t/m 4.4                                |
| `monitoring/`                        | Kinesis stream (CLI-script) voor de docker logs (week 6.1)     |
| `log-analysis/`                      | Logfile-analyse met IsolationForest (week 6.5)                 |
| `docs/week6-monitoring-logging.md`   | Uitwerking opdracht 6.1, 6.4 en 6.5                            |

Begin bij [docs/01-omgeving-herbouwen.md](docs/01-omgeving-herbouwen.md).
