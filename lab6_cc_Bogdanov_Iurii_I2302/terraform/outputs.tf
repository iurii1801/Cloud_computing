output "vpc_id" {
  description = "ID созданной VPC"
  value       = aws_vpc.lab6_vpc.id
}

output "public_subnet_ids" {
  description = "IDs публичных подсетей"
  value = [
    aws_subnet.public_1.id,
    aws_subnet.public_2.id,
  ]
}

output "private_subnet_ids" {
  description = "IDs приватных подсетей"
  value = [
    aws_subnet.private_1.id,
    aws_subnet.private_2.id,
  ]
}

output "web_instance_public_ip" {
  description = "Public IP веб-сервера"
  value       = aws_instance.web_server.public_ip
}

output "web_instance_public_dns" {
  description = "Public DNS веб-сервера"
  value       = aws_instance.web_server.public_dns
}
