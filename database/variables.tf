variable "region" {
  type    = string
  default = "us-east-1"
}

variable "db_username" {
  type    = string
  default = "admin"
}

# Geen default: Terraform vraagt erom, of zet TF_VAR_db_password in je shell.
variable "db_password" {
  type      = string
  sensitive = true
}

# Alleen de application tier subnets (zie infra/) mogen de database benaderen.
variable "app_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}
