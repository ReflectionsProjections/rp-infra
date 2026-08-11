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

output "rp_api_public_ip" {
  description = "Elastic IP attached to the RP API instance."
  value       = module.rp_api.public_ip
}

output "rp_api_codedeploy_app_name" {
  description = "CodeDeploy application name for the RP API host."
  value       = module.rp_api.codedeploy_app_name
}

output "rp_api_codedeploy_deployment_group" {
  description = "CodeDeploy deployment group for the RP API host."
  value       = module.rp_api.codedeploy_deployment_group_name
}

output "rp_api_codedeploy_artifact_bucket" {
  description = "S3 bucket used by CI to upload RP API CodeDeploy revision bundles."
  value       = var.rp_api_codedeploy_artifact_bucket
}

output "rp_api_resume_bucket" {
  description = "S3 bucket for this event year's resume uploads. Must match S3_BUCKET_NAME in the rp-api/prod/env secret."
  value       = aws_s3_bucket.rp_api_resumes.bucket
}

output "rp_api_supabase_backup_bucket" {
  description = "S3 bucket the Supabase backup script uploads to."
  value       = aws_s3_bucket.rp_api_supabase_backups.bucket
}

output "rp_api_env_secret_arn" {
  description = "Secrets Manager secret that must hold the RP API .env file content."
  value       = aws_secretsmanager_secret.rp_api_env.arn
}

output "rp_api_firebase_admin_cert_secret_arn" {
  description = "Secrets Manager secret that must hold the Firebase admin certificate JSON."
  value       = aws_secretsmanager_secret.rp_api_firebase_admin_cert.arn
}

output "github_deployer_user_name" {
  description = "IAM user for the GitHub Actions deploy workflows. Create its access key manually."
  value       = aws_iam_user.github_deployer.name
}
