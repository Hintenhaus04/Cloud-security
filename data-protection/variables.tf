variable "region" {
  type    = string
  default = "us-east-1"
}

# Mailadres voor de alert bij het lezen van een geheim object (bevestig de mail van AWS SNS).
variable "alert_email" {
  type = string
}

# Zet op false als het Learner Lab de EventBridge rule weigert (opdracht 4.4).
variable "enable_alerting" {
  type    = bool
  default = true
}
