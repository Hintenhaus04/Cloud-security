locals {
  web_servers = {
    web01 = aws_subnet.saxit_subnet_presentation_1.id
    web02 = aws_subnet.saxit_subnet_presentation_2.id
  }
  app_servers = {
    app01 = aws_subnet.saxit_subnet_appl_1.id
    app02 = aws_subnet.saxit_subnet_appl_2.id
  }
  instance_profile = var.instance_profile == "" ? null : var.instance_profile
}

##################################################
# Bastion host (week 1.3): enige SSH-ingang van de omgeving.
# Gebruik ProxyJump, dan blijft je private key op je eigen laptop:
#   ssh -J ubuntu@<bastion_ip> ubuntu@<prive_ip_van_vm>
resource "aws_instance" "bastion" {
  ami                    = var.ami
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.saxit_subnet_presentation_1.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  key_name               = var.key_name
  user_data              = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get upgrade -y
  EOF
  tags = {
    Name = "bastion"
  }
}

##################################################
# Webservers (presentation tier). De React frontend praat via nginx op dezelfde
# webserver met /api; nginx stuurt dat door naar de interne application-lb.
resource "aws_instance" "web" {
  for_each               = local.web_servers
  ami                    = var.ami
  instance_type          = var.instance_type
  subnet_id              = each.value
  vpc_security_group_ids = [aws_security_group.presentationtier_sg.id]
  key_name               = var.key_name
  iam_instance_profile   = local.instance_profile
  root_block_device {
    volume_type = "gp2"
    volume_size = 50
  }
  user_data = templatefile("${path.module}/templates/web.sh.tftpl", {
    app_lb_dns   = aws_lb.application-lb.dns_name
    dns_resolver = cidrhost(aws_vpc.saxit_vpc.cidr_block, 2)
    kinesis_setup = var.kinesis_stream_name == "" ? "" : templatefile("${path.module}/templates/kinesis-agent.sh.tftpl", {
      container   = "frontend"
      hostname    = each.key
      region      = var.region
      stream_name = var.kinesis_stream_name
    })
  })
  tags = {
    Name = each.key
  }
}

##################################################
# App servers (application tier) in de private subnets
resource "aws_instance" "app" {
  for_each               = local.app_servers
  ami                    = var.ami
  instance_type          = var.instance_type
  subnet_id              = each.value
  vpc_security_group_ids = [aws_security_group.applicationtier_sg.id]
  key_name               = var.key_name
  iam_instance_profile   = local.instance_profile
  root_block_device {
    volume_type = "gp2"
    volume_size = 50
  }
  user_data = templatefile("${path.module}/templates/app.sh.tftpl", {
    db_address  = data.aws_db_instance.db.address
    db_name     = var.db_name
    db_username = var.db_username
    db_password = var.db_password
    kinesis_setup = var.kinesis_stream_name == "" ? "" : templatefile("${path.module}/templates/kinesis-agent.sh.tftpl", {
      container   = "backend"
      hostname    = each.key
      region      = var.region
      stream_name = var.kinesis_stream_name
    })
  })
  tags = {
    Name = each.key
  }

  # Zonder NAT-route kan de user_data niets downloaden.
  depends_on = [aws_route_table_association.applicationtier1, aws_route_table_association.applicationtier2]
}
