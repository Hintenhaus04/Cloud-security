output "presentation_lb_url" {
  value = "http://${aws_lb.presentation-lb.dns_name}"
}

output "application_lb_dns" {
  value = aws_lb.application-lb.dns_name
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "web_private_ips" {
  value = { for name, vm in aws_instance.web : name => vm.private_ip }
}

output "app_private_ips" {
  value = { for name, vm in aws_instance.app : name => vm.private_ip }
}

output "ssh_example" {
  value = "ssh-add <key>.pem && ssh -J ubuntu@${aws_instance.bastion.public_ip} ubuntu@${aws_instance.app["app01"].private_ip}"
}
