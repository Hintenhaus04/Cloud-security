variable "region" {
  type    = string
  default = "us-east-1"
}

# Naam van het key pair dat je in de console hebt aangemaakt (handleiding stap 2).
variable "key_name" {
  type    = string
  default = "key1"
}

# Publiek IP-adres van waaruit je mag SSH'en naar de bastion host, bv. "84.12.34.56/32".
# Zoek je eigen IP op met: curl -s https://checkip.amazonaws.com
variable "admin_cidr" {
  type = string
}

variable "ami" {
  type    = string
  default = "ami-084568db4383264d4" # Ubuntu 24.04 LTS (us-east-1)
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

# Instance profile dat in het Learner Lab al bestaat. Nodig vanaf week 6 (Kinesis agent).
# Zet op "" als je geen instance profile wilt koppelen.
variable "instance_profile" {
  type    = string
  default = "LabInstanceProfile"
}

variable "db_name" {
  type    = string
  default = "cloudsecdb"
}

variable "db_username" {
  type    = string
  default = "admin"
}

variable "db_password" {
  type      = string
  sensitive = true
}
