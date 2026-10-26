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

Begin bij [docs/01-omgeving-herbouwen.md](docs/01-omgeving-herbouwen.md).
