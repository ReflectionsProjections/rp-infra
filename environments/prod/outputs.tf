// environments/prod/output.tf
output "hermes_public_ip" {
  description = "Elastic IP attached to the Hermes API instance."
  value       = module.hermes_api.public_ip
}

output "hermes_codedeploy_app_name" {
  description = "CodeDeploy application name for Hermes."
  value       = module.hermes_api.codedeploy_app_name
}

output "hermes_codedeploy_deployment_group" {
  description = "CodeDeploy deployment group for Hermes."
  value       = module.hermes_api.codedeploy_deployment_group_name
}

output "hermes_codedeploy_artifact_bucket" {
  description = "Existing S3 bucket used by CI to upload Hermes CodeDeploy revision bundles."
  value       = var.hermes_codedeploy_artifact_bucket
}

# output "rp_api_public_ip" {
#   description = "Elastic IP attached to the RP API instance."
#   value       = module.rp_api.public_ip
# }
#
# output "rp_api_codedeploy_app_name" {
#   description = "CodeDeploy application name for rp-api."
#   value       = module.rp_api.codedeploy_app_name
# }
#
# output "rp_api_codedeploy_deployment_group" {
#   description = "CodeDeploy deployment group for rp-api."
#   value       = module.rp_api.codedeploy_deployment_group_name
# }
