terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "3.66.0"
    }
  }
}
provider "aws" {
  region  = "us-east-1"
  profile = "254285977890"
}

###################################################
#Create a standard VPC
resource "aws_vpc" "saxit_vpc_db" {
  cidr_block = "10.1.0.0/16"

  tags = {
    Name  = "saxit_vpc_db"
  }
}
###################################################
#Create different databasetier subnets spread over 2 different availability zones 
resource "aws_subnet" "saxit_subnet_db_1" {
  vpc_id            = aws_vpc.saxit_vpc_db.id
  cidr_block        = "10.1.5.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name  = "saxit_subnet_db_1"
  }
}

resource "aws_subnet" "saxit_subnet_db_2" {
  vpc_id            = aws_vpc.saxit_vpc_db.id
  cidr_block        = "10.1.6.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name  = "saxit_subnet_db_2"
  }
}

resource "aws_db_subnet_group" "my_db_subnet_group" {
  name = "my-db-subnet-group"
  subnet_ids = [aws_subnet.saxit_subnet_db_1.id, aws_subnet.saxit_subnet_db_2.id]

  tags = {
    Name = "My DB Subnet Group"
  }
}

###################################################
# Create security group DB
resource "aws_security_group" "rdssecuritygroup" {
  name        = "rds_security_group"
  description = "Allow inbound traffic only for MYSQL and all outbound traffic"
  vpc_id      = aws_vpc.saxit_vpc_db.id
  tags = {
    Name = "rds_security_group"
  }
ingress {
   description = "SQL ingress"
   from_port   = 3306
   to_port     = 3306
   protocol    = "tcp"
   cidr_blocks = ["0.0.0.0/0"]
 }

egress {
   from_port   = 0
   to_port     = 0
   protocol    = "-1"
   cidr_blocks = ["0.0.0.0/0"]
 }
}

###################################################
#Create RDS database
resource "aws_db_instance" "cloudsecdb" {
  identifier             = "cloudsecdb"
  allocated_storage      = 10
  engine                 = "mysql"
  instance_class         = "db.t3.micro"
  username               = "admin"
  password               = "password123"
  name                   = "cloudsecdb"
  vpc_security_group_ids = [aws_security_group.rdssecuritygroup.id]
  db_subnet_group_name   = aws_db_subnet_group.my_db_subnet_group.name
  skip_final_snapshot    = true
}