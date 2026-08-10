// environments/prod/main.tf
data "aws_iam_policy_document" "codedeploy_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codedeploy.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codedeploy_service" {
  name               = "${var.project_name}-${var.environment}-codedeploy-service-role"
  assume_role_policy = data.aws_iam_policy_document.codedeploy_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "codedeploy_service" {
  role       = aws_iam_role.codedeploy_service.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

module "hermes_api" {
  source = "../../modules/ec2_api_service"

  aws_region                  = var.aws_region
  environment                 = var.environment
  service_name                = "hermes-api"
  domain_name                 = var.hermes_domain_name
  app_port                    = 5555
  deployment_path             = "/home/ubuntu/hermes"
  healthcheck_path            = "/"
  instance_type               = "t2.small"
  key_name                    = var.key_name
  ssh_cidr_blocks             = var.ssh_cidr_blocks
  use_letsencrypt             = true
  letsencrypt_email           = var.hermes_letsencrypt_email
  codedeploy_service_role_arn = aws_iam_role.codedeploy_service.arn
  extra_tags                  = local.common_tags
}

// Secret shells only. Terraform never reads or writes the secret values, so
// they stay out of the state file. Load the values manually in the AWS console
// or CLI. The names must match services/api/scripts/load_env.sh in rp-monorepo.
resource "aws_secretsmanager_secret" "rp_api_env" {
  name = "rp-api/prod/env"
  tags = local.common_tags
}

resource "aws_secretsmanager_secret" "rp_api_firebase_admin_cert" {
  name = "rp-api/prod/firebase-admin-cert"
  tags = local.common_tags
}

// Private bucket for the manual Supabase backup script on the rp-api host.
// The ec2_api_service module grants the instance role s3:PutObject on it.
resource "aws_s3_bucket" "rp_api_supabase_backups" {
  bucket = var.rp_api_supabase_backup_bucket
  tags   = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "rp_api_supabase_backups" {
  bucket = aws_s3_bucket.rp_api_supabase_backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "rp_api_supabase_backups" {
  bucket = aws_s3_bucket.rp_api_supabase_backups.id

  rule {
    id     = "expire-old-backups"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }
  }
}

module "rp_api" {
  source = "../../modules/ec2_api_service"

  aws_region                        = var.aws_region
  environment                       = var.environment
  service_name                      = "rp-api"
  domain_name                       = var.rp_api_domain_name
  app_port                          = 3000
  deployment_path                   = "/home/ubuntu/rp-api"
  healthcheck_path                  = "/status"
  instance_type                     = "t2.micro"
  key_name                          = var.key_name
  ssh_cidr_blocks                   = var.ssh_cidr_blocks
  use_letsencrypt                   = true
  letsencrypt_email                 = var.rp_api_letsencrypt_email
  install_supabase_backup_script    = true
  supabase_backup_env_path          = "/etc/rp-api/supabase-backup.env"
  supabase_backup_bucket            = aws_s3_bucket.rp_api_supabase_backups.bucket
  install_cloudwatch_agent          = true
  create_codedeploy_artifact_bucket = true
  codedeploy_artifact_bucket_name   = var.rp_api_codedeploy_artifact_bucket
  codedeploy_service_role_arn       = aws_iam_role.codedeploy_service.arn
  secretsmanager_secret_arns = [
    aws_secretsmanager_secret.rp_api_env.arn,
    aws_secretsmanager_secret.rp_api_firebase_admin_cert.arn,
  ]
  extra_tags = local.common_tags
}

// IAM user for the GitHub Actions deploy workflows. Both deploy workflows in
// this repo share the AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY repo secrets,
// so this one user covers rp-api and Hermes. Terraform does not create the
// access key; make one in the console and store it in repo secrets.
data "aws_caller_identity" "current" {}

resource "aws_iam_user" "github_deployer" {
  name = "rp-github-deployer"
  tags = local.common_tags
}

data "aws_iam_policy_document" "github_deployer" {
  statement {
    sid = "UploadArtifacts"
    actions = [
      "s3:PutObject",
      "s3:AbortMultipartUpload",
    ]
    resources = [
      "arn:aws:s3:::${var.rp_api_codedeploy_artifact_bucket}/*",
      "arn:aws:s3:::${var.hermes_codedeploy_artifact_bucket}/*",
    ]
  }

  statement {
    sid = "StartDeployments"
    actions = [
      "codedeploy:CreateDeployment",
      "codedeploy:GetDeployment",
      "codedeploy:GetApplicationRevision",
      "codedeploy:RegisterApplicationRevision",
      "codedeploy:ListDeployments",
    ]
    resources = [
      module.rp_api.codedeploy_app_arn,
      module.rp_api.codedeploy_deployment_group_arn,
      module.hermes_api.codedeploy_app_arn,
      module.hermes_api.codedeploy_deployment_group_arn,
    ]
  }

  statement {
    sid       = "ReadDeploymentConfig"
    actions   = ["codedeploy:GetDeploymentConfig"]
    resources = ["arn:aws:codedeploy:${var.aws_region}:${data.aws_caller_identity.current.account_id}:deploymentconfig:*"]
  }
}

resource "aws_iam_user_policy" "github_deployer" {
  name   = "rp-github-deployer"
  user   = aws_iam_user.github_deployer.name
  policy = data.aws_iam_policy_document.github_deployer.json
}
