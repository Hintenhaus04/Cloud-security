###################################################
#Lookup resources created by database/ (apply database/ first)
data "aws_vpc" "db" {
  tags = {
    Name = "saxit_vpc_db"
  }
}

data "aws_route_table" "db_main" {
  vpc_id = data.aws_vpc.db.id
  filter {
    name   = "association.main"
    values = ["true"]
  }
}

data "aws_db_instance" "db" {
  db_instance_identifier = "cloudsecdb"
}
###################################################
#Create a standard VPC
resource "aws_vpc" "saxit_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "saxit_vpc"
  }
}

###################################################
#Create an internetgateway in de VPC
resource "aws_internet_gateway" "saxit_gw" {
  vpc_id = aws_vpc.saxit_vpc.id

  tags = {
    Name = "saxit_gw"
  }
}
###################################################
#Create peering with db VPC
resource "aws_vpc_peering_connection" "dbpeer" {
  vpc_id      = aws_vpc.saxit_vpc.id
  peer_vpc_id = data.aws_vpc.db.id
  auto_accept = true

  tags = {
    Name = "saxit_dbpeer"
  }
}

###################################################
#Create different presentationtier subnets spread over 2 different availability zones
#(publiek: hier staan de presentation load balancer, de webservers, de bastion host en de NAT gateway)
resource "aws_subnet" "saxit_subnet_presentation_1" {
  vpc_id                  = aws_vpc.saxit_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags = {
    Name = "saxit_subnet_presentation_1"
  }
}

resource "aws_subnet" "saxit_subnet_presentation_2" {
  vpc_id                  = aws_vpc.saxit_vpc.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1b"
  tags = {
    Name = "saxit_subnet_presentation_2"
  }
}

###################################################
#Create different applicationtier subnets spread over 2 different availability zones
#(privaat: geen publieke IP's, internet alleen uitgaand via de NAT gateway)
resource "aws_subnet" "saxit_subnet_appl_1" {
  vpc_id            = aws_vpc.saxit_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "saxit_subnet_appl_1"
  }
}

resource "aws_subnet" "saxit_subnet_appl_2" {
  vpc_id            = aws_vpc.saxit_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "saxit_subnet_appl_2"
  }
}

###################################################
#NAT gateway zodat de application servers wel updates/images kunnen ophalen,
#maar niet vanaf internet bereikbaar zijn
resource "aws_eip" "nat" {
  vpc = true

  tags = {
    Name = "saxit_nat_eip"
  }
}

resource "aws_nat_gateway" "saxit_nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.saxit_subnet_presentation_1.id
  depends_on    = [aws_internet_gateway.saxit_gw]

  tags = {
    Name = "saxit_nat"
  }
}

###################################################
# Create routing table for presentationtier
resource "aws_route_table" "pres-route" {
  vpc_id = aws_vpc.saxit_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.saxit_gw.id
  }
  tags = {
    Name = "pres-route"
  }
}

###################################################
# Create routing table for applicationtier
# Alleen de application tier heeft een route naar de database VPC.
resource "aws_route_table" "appl-route" {
  vpc_id = aws_vpc.saxit_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.saxit_nat.id
  }
  route {
    cidr_block                = data.aws_vpc.db.cidr_block
    vpc_peering_connection_id = aws_vpc_peering_connection.dbpeer.id
  }
  tags = {
    Name = "appl-route"
  }
}

###################################################
# Routes in db VPC: alleen terug naar de application tier subnets
resource "aws_route" "dbroute_appl_1" {
  route_table_id            = data.aws_route_table.db_main.id
  destination_cidr_block    = aws_subnet.saxit_subnet_appl_1.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.dbpeer.id
}

resource "aws_route" "dbroute_appl_2" {
  route_table_id            = data.aws_route_table.db_main.id
  destination_cidr_block    = aws_subnet.saxit_subnet_appl_2.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.dbpeer.id
}

###################################################
#Connect routing tables to subnets
resource "aws_route_table_association" "presentationtier1" {
  subnet_id      = aws_subnet.saxit_subnet_presentation_1.id
  route_table_id = aws_route_table.pres-route.id
}
resource "aws_route_table_association" "presentationtier2" {
  subnet_id      = aws_subnet.saxit_subnet_presentation_2.id
  route_table_id = aws_route_table.pres-route.id
}
resource "aws_route_table_association" "applicationtier1" {
  subnet_id      = aws_subnet.saxit_subnet_appl_1.id
  route_table_id = aws_route_table.appl-route.id
}
resource "aws_route_table_association" "applicationtier2" {
  subnet_id      = aws_subnet.saxit_subnet_appl_2.id
  route_table_id = aws_route_table.appl-route.id
}
