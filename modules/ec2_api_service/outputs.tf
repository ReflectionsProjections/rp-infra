//ec2_api_service/outputs.tf
output "instance_id" {
  description = "EC2 instance ID for the service."
  value       = aws_instance.this.id
}

output "public_ip" {
  description = "Elastic IP address attached to the service instance."
  value       = aws_eip.this.public_ip
}

output "public_dns" {
  description = "Public DNS name of the EC2 instance."
  value       = aws_instance.this.public_dns
}

output "codedeploy_app_name" {
  description = "CodeDeploy application name for the service."
  value       = aws_codedeploy_app.this.name
}

output "codedeploy_deployment_group_name" {
  description = "CodeDeploy deployment group name for the service."
  value       = aws_codedeploy_deployment_group.this.deployment_group_name
}

output "deployment_path" {
  description = "Directory on the EC2 instance where CodeDeploy places the application."
  value       = var.deployment_path
}
