###################################################
# Create loadbalancer presentation tier (internet-facing)
resource "aws_lb" "presentation-lb" {
  name                       = "presentation-lb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.presentation_lb_sg.id]
  subnets                    = [aws_subnet.saxit_subnet_presentation_1.id, aws_subnet.saxit_subnet_presentation_2.id]
  enable_deletion_protection = false
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "presentation-lb-tg" {
  name        = "presentation-lb-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.saxit_vpc.id
  target_type = "instance"
  health_check {
    healthy_threshold   = "3"
    interval            = "30"
    protocol            = "HTTP"
    matcher             = "200"
    timeout             = "5"
    path                = "/"
    unhealthy_threshold = "2"
  }
}

resource "aws_alb_listener" "listener-http" {
  load_balancer_arn = aws_lb.presentation-lb.id
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.presentation-lb-tg.arn
  }
}

resource "aws_lb_target_group_attachment" "presentation-attach" {
  for_each         = aws_instance.web
  target_group_arn = aws_lb_target_group.presentation-lb-tg.arn
  target_id        = each.value.id
}

###################################################
# Create loadbalancer application tier (intern: alleen bereikbaar vanuit de VPC)
resource "aws_lb" "application-lb" {
  name                       = "application-lb"
  internal                   = true
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.application_lb_sg.id]
  subnets                    = [aws_subnet.saxit_subnet_appl_1.id, aws_subnet.saxit_subnet_appl_2.id]
  enable_deletion_protection = false
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "application-lb-tg" {
  name        = "application-lb-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.saxit_vpc.id
  target_type = "instance"
  health_check {
    healthy_threshold   = "3"
    interval            = "30"
    protocol            = "HTTP"
    matcher             = "200-499"
    timeout             = "5"
    path                = "/"
    unhealthy_threshold = "2"
  }
}

resource "aws_alb_listener" "listener-http-appl" {
  load_balancer_arn = aws_lb.application-lb.id
  port              = 8080
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.application-lb-tg.arn
  }
}

resource "aws_lb_target_group_attachment" "application-attach" {
  for_each         = aws_instance.app
  target_group_arn = aws_lb_target_group.application-lb-tg.arn
  target_id        = each.value.id
}
