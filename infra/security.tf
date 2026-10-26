###################################################
# Week 3: security groups
#
# North-South (internet <-> omgeving):
#   internet  -> presentation-lb  : 80
#   admin_cidr -> bastion         : 22
#   alle andere tiers zijn niet direct vanaf internet bereikbaar
#
# East-West (binnen de omgeving, microsegmentatie):
#   presentation-lb -> web       : 80
#   web             -> application-lb : 8080
#   application-lb  -> app       : 8080
#   app             -> database  : 3306 (zie database/rds.tf)
#   bastion         -> web, app  : 22 (+ ping)
#
# Uitgaand naar internet alleen 80/443 voor updates, Docker images, npm en Maven.
# Regels staan in losse aws_security_group_rule resources omdat de groepen naar elkaar verwijzen.
###################################################

resource "aws_security_group" "bastion_sg" {
  name        = "bastion_sg"
  description = "SSH from admin to bastion, SSH from bastion to tiers"
  vpc_id      = aws_vpc.saxit_vpc.id
  tags = {
    Name = "bastion_sg"
  }
}

resource "aws_security_group" "presentation_lb_sg" {
  name        = "presentation_lb_sg"
  description = "HTTP from internet to presentation load balancer"
  vpc_id      = aws_vpc.saxit_vpc.id
  tags = {
    Name = "presentation_lb_sg"
  }
}

resource "aws_security_group" "presentationtier_sg" {
  name        = "presentationtier_sg"
  description = "HTTP from presentation-lb, SSH from bastion"
  vpc_id      = aws_vpc.saxit_vpc.id
  tags = {
    Name = "presentationtier_sg"
  }
}

resource "aws_security_group" "application_lb_sg" {
  name        = "application_lb_sg"
  description = "8080 from web servers to internal application load balancer"
  vpc_id      = aws_vpc.saxit_vpc.id
  tags = {
    Name = "application_lb_sg"
  }
}

resource "aws_security_group" "applicationtier_sg" {
  name        = "applicationtier_sg"
  description = "8080 from application-lb, SSH from bastion"
  vpc_id      = aws_vpc.saxit_vpc.id
  tags = {
    Name = "applicationtier_sg"
  }
}

###################################################
# Bastion host
resource "aws_security_group_rule" "bastion_in_ssh" {
  description       = "SSH from admin"
  type              = "ingress"
  security_group_id = aws_security_group.bastion_sg.id
  protocol          = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_blocks       = [var.admin_cidr]
}

resource "aws_security_group_rule" "bastion_out_ssh_web" {
  description              = "SSH to web servers"
  type                     = "egress"
  security_group_id        = aws_security_group.bastion_sg.id
  protocol                 = "tcp"
  from_port                = 22
  to_port                  = 22
  source_security_group_id = aws_security_group.presentationtier_sg.id
}

resource "aws_security_group_rule" "bastion_out_ssh_app" {
  description              = "SSH to app servers"
  type                     = "egress"
  security_group_id        = aws_security_group.bastion_sg.id
  protocol                 = "tcp"
  from_port                = 22
  to_port                  = 22
  source_security_group_id = aws_security_group.applicationtier_sg.id
}

resource "aws_security_group_rule" "bastion_out_ping_web" {
  description              = "Ping to web servers"
  type                     = "egress"
  security_group_id        = aws_security_group.bastion_sg.id
  protocol                 = "icmp"
  from_port                = 8
  to_port                  = 0
  source_security_group_id = aws_security_group.presentationtier_sg.id
}

resource "aws_security_group_rule" "bastion_out_ping_app" {
  description              = "Ping to app servers"
  type                     = "egress"
  security_group_id        = aws_security_group.bastion_sg.id
  protocol                 = "icmp"
  from_port                = 8
  to_port                  = 0
  source_security_group_id = aws_security_group.applicationtier_sg.id
}

resource "aws_security_group_rule" "bastion_out_web" {
  description       = "HTTP/HTTPS for updates"
  for_each          = toset(["80", "443"])
  type              = "egress"
  security_group_id = aws_security_group.bastion_sg.id
  protocol          = "tcp"
  from_port         = each.value
  to_port           = each.value
  cidr_blocks       = ["0.0.0.0/0"]
}

###################################################
# Presentation load balancer
resource "aws_security_group_rule" "presentation_lb_in_http" {
  description       = "HTTP from internet"
  type              = "ingress"
  security_group_id = aws_security_group.presentation_lb_sg.id
  protocol          = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "presentation_lb_out_web" {
  description              = "HTTP to web servers"
  type                     = "egress"
  security_group_id        = aws_security_group.presentation_lb_sg.id
  protocol                 = "tcp"
  from_port                = 80
  to_port                  = 80
  source_security_group_id = aws_security_group.presentationtier_sg.id
}

###################################################
# Web servers (presentation tier)
resource "aws_security_group_rule" "web_in_http" {
  description              = "HTTP from presentation-lb"
  type                     = "ingress"
  security_group_id        = aws_security_group.presentationtier_sg.id
  protocol                 = "tcp"
  from_port                = 80
  to_port                  = 80
  source_security_group_id = aws_security_group.presentation_lb_sg.id
}

resource "aws_security_group_rule" "web_in_ssh" {
  description              = "SSH from bastion"
  type                     = "ingress"
  security_group_id        = aws_security_group.presentationtier_sg.id
  protocol                 = "tcp"
  from_port                = 22
  to_port                  = 22
  source_security_group_id = aws_security_group.bastion_sg.id
}

resource "aws_security_group_rule" "web_in_ping" {
  description              = "Ping from bastion"
  type                     = "ingress"
  security_group_id        = aws_security_group.presentationtier_sg.id
  protocol                 = "icmp"
  from_port                = 8
  to_port                  = 0
  source_security_group_id = aws_security_group.bastion_sg.id
}

resource "aws_security_group_rule" "web_out_api" {
  description              = "API calls to application-lb"
  type                     = "egress"
  security_group_id        = aws_security_group.presentationtier_sg.id
  protocol                 = "tcp"
  from_port                = 8080
  to_port                  = 8080
  source_security_group_id = aws_security_group.application_lb_sg.id
}

resource "aws_security_group_rule" "web_out_web" {
  description       = "HTTP/HTTPS for updates and builds"
  for_each          = toset(["80", "443"])
  type              = "egress"
  security_group_id = aws_security_group.presentationtier_sg.id
  protocol          = "tcp"
  from_port         = each.value
  to_port           = each.value
  cidr_blocks       = ["0.0.0.0/0"]
}

###################################################
# Application load balancer (intern)
resource "aws_security_group_rule" "application_lb_in_api" {
  description              = "API calls from web servers"
  type                     = "ingress"
  security_group_id        = aws_security_group.application_lb_sg.id
  protocol                 = "tcp"
  from_port                = 8080
  to_port                  = 8080
  source_security_group_id = aws_security_group.presentationtier_sg.id
}

resource "aws_security_group_rule" "application_lb_out_app" {
  description              = "8080 to app servers"
  type                     = "egress"
  security_group_id        = aws_security_group.application_lb_sg.id
  protocol                 = "tcp"
  from_port                = 8080
  to_port                  = 8080
  source_security_group_id = aws_security_group.applicationtier_sg.id
}

###################################################
# App servers (application tier)
resource "aws_security_group_rule" "app_in_api" {
  description              = "8080 from application-lb"
  type                     = "ingress"
  security_group_id        = aws_security_group.applicationtier_sg.id
  protocol                 = "tcp"
  from_port                = 8080
  to_port                  = 8080
  source_security_group_id = aws_security_group.application_lb_sg.id
}

resource "aws_security_group_rule" "app_in_ssh" {
  description              = "SSH from bastion"
  type                     = "ingress"
  security_group_id        = aws_security_group.applicationtier_sg.id
  protocol                 = "tcp"
  from_port                = 22
  to_port                  = 22
  source_security_group_id = aws_security_group.bastion_sg.id
}

resource "aws_security_group_rule" "app_in_ping" {
  description              = "Ping from bastion"
  type                     = "ingress"
  security_group_id        = aws_security_group.applicationtier_sg.id
  protocol                 = "icmp"
  from_port                = 8
  to_port                  = 0
  source_security_group_id = aws_security_group.bastion_sg.id
}

resource "aws_security_group_rule" "app_out_db" {
  description       = "MySQL to database VPC"
  type              = "egress"
  security_group_id = aws_security_group.applicationtier_sg.id
  protocol          = "tcp"
  from_port         = 3306
  to_port           = 3306
  cidr_blocks       = [data.aws_vpc.db.cidr_block]
}

resource "aws_security_group_rule" "app_out_web" {
  description       = "HTTP/HTTPS via NAT for updates and builds"
  for_each          = toset(["80", "443"])
  type              = "egress"
  security_group_id = aws_security_group.applicationtier_sg.id
  protocol          = "tcp"
  from_port         = each.value
  to_port           = each.value
  cidr_blocks       = ["0.0.0.0/0"]
}
