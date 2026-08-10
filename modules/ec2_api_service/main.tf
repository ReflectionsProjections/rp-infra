//ec2_api_service/main.tf
locals {
  cert_path = var.tls_certificate_path != "" ? var.tls_certificate_path : "/etc/nginx/ssl/${var.service_name}/origin.crt"
  key_path  = var.tls_private_key_path != "" ? var.tls_private_key_path : "/etc/nginx/ssl/${var.service_name}/origin.key"
  supabase_backup_script = var.install_supabase_backup_script ? templatefile("${path.module}/templates/supabase_backups.sh.tftpl", {
    supabase_backup_env_path = var.supabase_backup_env_path
  }) : ""

  service_tags = merge(var.extra_tags, {
    Name        = var.service_name
    Service     = var.service_name
    Environment = var.environment
  })

  nginx_conf = templatefile("${path.module}/templates/nginx.conf.tftpl", {
    app_port             = var.app_port
    domain_name          = var.domain_name
    healthcheck_path     = var.healthcheck_path
    tls_certificate_path = local.cert_path
    tls_private_key_path = local.key_path
  })
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_security_group" "this" {
  name        = "${var.service_name}-sg"
  description = "Security group for ${var.service_name}"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = toset(var.ssh_cidr_blocks)

    content {
      description = "SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.service_tags
}

resource "aws_iam_role" "instance" {
  name               = "${var.service_name}-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = local.service_tags
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.service_name}-instance-profile"
  role = aws_iam_role.instance.name
  tags = local.service_tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "codedeploy" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforAWSCodeDeploy"
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy" "secrets_read" {
  count = length(var.secretsmanager_secret_arns) > 0 ? 1 : 0

  name = "${var.service_name}-secrets-read"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = var.secretsmanager_secret_arns
      }
    ]
  })
}

resource "aws_iam_role_policy" "supabase_backup_s3" {
  count = var.supabase_backup_bucket != "" ? 1 : 0

  name = "${var.service_name}-supabase-backup-s3"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "arn:aws:s3:::${var.supabase_backup_bucket}/*"
      }
    ]
  })
}

resource "aws_s3_bucket" "codedeploy_artifacts" {
  count = var.create_codedeploy_artifact_bucket ? 1 : 0

  bucket = var.codedeploy_artifact_bucket_name
  tags   = local.service_tags
}

resource "aws_s3_bucket_public_access_block" "codedeploy_artifacts" {
  count = var.create_codedeploy_artifact_bucket ? 1 : 0

  bucket = aws_s3_bucket.codedeploy_artifacts[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "codedeploy_artifacts" {
  count = var.create_codedeploy_artifact_bucket ? 1 : 0

  bucket = aws_s3_bucket.codedeploy_artifacts[0].id

  rule {
    id     = "expire-old-bundles"
    status = "Enabled"

    filter {}

    expiration {
      days = 60
    }
  }
}

resource "aws_instance" "this" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.this.id]
  iam_instance_profile        = aws_iam_instance_profile.this.name
  key_name                    = var.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size = var.root_volume_size_gb
  }

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    aws_region                     = var.aws_region
    deployment_path                = var.deployment_path
    domain_name                    = var.domain_name
    install_cloudwatch_agent       = var.install_cloudwatch_agent
    install_supabase_backup_script = var.install_supabase_backup_script
    letsencrypt_email              = var.letsencrypt_email
    nginx_conf_base64              = base64encode(local.nginx_conf)
    service_name                   = var.service_name
    supabase_backup_env_path       = var.supabase_backup_env_path
    supabase_backup_script_base64  = base64encode(local.supabase_backup_script)
    tls_certificate_path           = local.cert_path
    tls_private_key_path           = local.key_path
    use_letsencrypt                = var.use_letsencrypt
  })

  tags = local.service_tags

  // These hosts are stateful pets: Hermes keeps a manual .env on disk and
  // both keep TLS certs. A newer "most recent" AMI or an edited bootstrap
  // script must not replace or restart a running instance. Both only take
  // effect at first boot anyway. To rebuild a host on purpose, taint it:
  //   terraform taint module.<service>.aws_instance.this
  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

resource "aws_eip" "this" {
  domain = "vpc"
  tags   = local.service_tags
}

resource "aws_eip_association" "this" {
  instance_id   = aws_instance.this.id
  allocation_id = aws_eip.this.id
}

resource "aws_codedeploy_app" "this" {
  compute_platform = "Server"
  name             = "${var.service_name}-codedeploy-app"
}

resource "aws_codedeploy_deployment_group" "this" {
  app_name               = aws_codedeploy_app.this.name
  deployment_group_name  = "${var.service_name}-deployment-group"
  service_role_arn       = var.codedeploy_service_role_arn
  deployment_config_name = "CodeDeployDefault.OneAtATime"

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM", "DEPLOYMENT_STOP_ON_REQUEST"]
  }

  // CodeDeploy ORs the filters inside one ec2_tag_set and ANDs separate sets.
  // Keep each filter in its own set so an instance must match Service AND
  // Environment, not either one.
  ec2_tag_set {
    ec2_tag_filter {
      key   = "Service"
      type  = "KEY_AND_VALUE"
      value = var.service_name
    }
  }

  ec2_tag_set {
    ec2_tag_filter {
      key   = "Environment"
      type  = "KEY_AND_VALUE"
      value = var.environment
    }
  }
}
