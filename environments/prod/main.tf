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

// Postgres connection values for the Supabase backup script
// (services/api/scripts/supabase_backups.sh in rp-monorepo). Load plaintext
// env lines: DB_HOST, DB_PORT, DB_USER, DB_NAME, DB_PASSWORD. These are the
// database's own credentials from the Supabase dashboard — they are not in
// the app env secret, which only holds the Supabase URL and service key.
resource "aws_secretsmanager_secret" "rp_api_supabase_backup_env" {
  name = "rp-api/prod/supabase-backup-env"
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

// Resume uploads bucket for the current event year. Past years' buckets
// (rp-2023-resumes .. rp-2025-resumes) were created by hand and stay outside
// terraform. The API reaches the bucket with the rp-api IAM user's keys, so
// switching years means: create the new bucket here, update S3_BUCKET_NAME in
// the rp-api/prod/env secret, redeploy. CORS mirrors the 2025 bucket because
// the frontend uploads resumes straight to S3 with presigned POSTs.
resource "aws_s3_bucket" "rp_api_resumes" {
  bucket = var.rp_api_resume_bucket
  tags   = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "rp_api_resumes" {
  bucket = aws_s3_bucket.rp_api_resumes.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "rp_api_resumes" {
  bucket = aws_s3_bucket.rp_api_resumes.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "GET"]
    allowed_origins = ["*"]
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
  root_volume_size_gb               = 16
  key_name                          = var.key_name
  ssh_cidr_blocks                   = var.ssh_cidr_blocks
  use_letsencrypt                   = true
  letsencrypt_email                 = var.rp_api_letsencrypt_email
  install_supabase_backup_tools     = true
  supabase_backup_bucket            = aws_s3_bucket.rp_api_supabase_backups.bucket
  install_cloudwatch_agent          = true
  create_codedeploy_artifact_bucket = true
  codedeploy_artifact_bucket_name   = var.rp_api_codedeploy_artifact_bucket
  codedeploy_service_role_arn       = aws_iam_role.codedeploy_service.arn
  secretsmanager_secret_arns = [
    aws_secretsmanager_secret.rp_api_env.arn,
    aws_secretsmanager_secret.rp_api_firebase_admin_cert.arn,
    aws_secretsmanager_secret.rp_api_supabase_backup_env.arn,
  ]
  extra_tags = local.common_tags
}

data "aws_caller_identity" "current" {}

// GitHub Actions authenticates to AWS with OIDC: the deploy workflow assumes
// github_deployer_role via AssumeRoleWithWebIdentity, so no long-lived access
// keys exist. The trust policy only accepts tokens minted for the main branch
// of rp-infra.
resource "aws_iam_openid_connect_provider" "github_actions" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  // AWS validates GitHub's OIDC issuer against its own trusted CAs and ignores
  // this value, but the provider still requires the field to be set.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
  tags            = local.common_tags
}

data "aws_iam_policy_document" "github_deployer_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:ReflectionsProjections/rp-infra:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_deployer_role" {
  name               = "rp-github-deployer"
  assume_role_policy = data.aws_iam_policy_document.github_deployer_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "github_deployer_role" {
  name   = "rp-github-deployer"
  role   = aws_iam_role.github_deployer_role.id
  policy = data.aws_iam_policy_document.github_deployer.json
}

// Legacy IAM user for the deploy workflow, superseded by github_deployer_role
// above. Kept until the OIDC path is verified end to end; then delete the
// user's access key in the console, remove this user (and the repo's
// AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY secrets), and apply again.
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
