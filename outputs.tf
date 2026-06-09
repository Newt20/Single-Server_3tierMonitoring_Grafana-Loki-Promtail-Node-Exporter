output "vpc_id" {
  description = "The ID of the VPC created for this project"
  value       = aws_vpc.nt-vpc.id
}

output "public_server_ip" {
  description = "The public IP address of the EC2 instance"
  value       = aws_instance.nt-Server.public_ip
}

output "frontend_url" {
  description = "The URL to access the web application"
  value       = "http://${aws_instance.nt-Server.public_ip}"
}