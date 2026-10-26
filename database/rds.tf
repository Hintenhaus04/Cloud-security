###################################################
#Create a standard VPC
resource "aws_vpc" "saxit_vpc_db" {
  cidr_block = "10.1.0.0/16"

  tags = {
    Name = "saxit_vpc_db"
  }
}
###################################################
#Create different databasetier subnets spread over 2 different availability zones 
resource "aws_subnet" "saxit_subnet_db_1" {
  vpc_id            = aws_vpc.saxit_vpc_db.id
  cidr_block        = "10.1.5.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "saxit_subnet_db_1"
  }
}

resource "aws_subnet" "saxit_subnet_db_2" {
  vpc_id            = aws_vpc.saxit_vpc_db.id
  cidr_block        = "10.1.6.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "saxit_subnet_db_2"
  }
}

resource "aws_db_subnet_group" "my_db_subnet_group" {
  name       = "my-db-subnet-group"
  subnet_ids = [aws_subnet.saxit_subnet_db_1.id, aws_subnet.saxit_subnet_db_2.id]

  tags = {
    Name = "My DB Subnet Group"
  }
}

###################################################
# Create security group DB (week 3: east-west)
# Alleen MySQL vanaf de application tier subnets, geen uitgaand verkeer nodig
# (security groups zijn stateful, antwoorden gaan altijd terug).
resource "aws_security_group" "rdssecuritygroup" {
  name        = "rds_security_group"
  description = "Allow MySQL only from the application tier subnets"
  vpc_id      = aws_vpc.saxit_vpc_db.id
  tags = {
    Name = "rds_security_group"
  }

  ingress {
    description = "MySQL from application tier"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = var.app_subnet_cidrs
  }
}

###################################################
#Create RDS database
resource "aws_db_instance" "cloudsecdb" {
  identifier             = "cloudsecdb"
  allocated_storage      = 10
  engine                 = "mysql"
  instance_class         = "db.t3.micro"
  username               = var.db_username
  password               = var.db_password
  name                   = "cloudsecdb"
  vpc_security_group_ids = [aws_security_group.rdssecuritygroup.id]
  db_subnet_group_name   = aws_db_subnet_group.my_db_subnet_group.name
  publicly_accessible    = false
  storage_encrypted      = true
  skip_final_snapshot    = true

  # Beschermt tegen een per ongeluk uitgevoerde terraform destroy in deze map.
  lifecycle {
    prevent_destroy = true
  }
}
