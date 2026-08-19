output "app_security_group_id" {
  value = aws_security_group.app.id
}

output "instance_id" {
  value = aws_instance.app.id
}

output "instance_private_ip" {
  value = aws_instance.app.private_ip
}