output "app_security_group_id" {
  value = aws_security_group.app.id
}

output "instance_ids" {
  value = aws_instance.app[*].id
}

output "instance_private_ips" {
  value = aws_instance.app[*].private_ip
}

output "alb_dns_name" {
  value = aws_lb.app.dns_name
}