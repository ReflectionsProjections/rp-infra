//ec2_api_service/main.tf
locals {
  cert_path = var.tls_certificate_path != "" ? var.tls_certificate_path : "/etc/nginx/ssl/${var.service_name}/origin.crt"
  key_path  = var.tls_private_key_path != "" ? var.tls_private_key_path : "/etc/nginx/ssl/${var.service_name}/origin.key"

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

resource "aws_instance" "this" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.this.id]
  iam_instance_profile        = aws_iam_instance_profile.this.name
  key_name                    = var.key_name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    aws_region            = var.aws_region
    deployment_path       = var.deployment_path
    domain_name           = var.domain_name
    nginx_conf_base64     = base64encode(local.nginx_conf)
    service_name          = var.service_name
    tls_certificate_path  = local.cert_path
    tls_private_key_path  = local.key_path
  })

  tags = local.service_tags
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

  ec2_tag_set {
    ec2_tag_filter {
      key   = "Service"
      type  = "KEY_AND_VALUE"
      value = var.service_name
    }

    ec2_tag_filter {
      key   = "Environment"
      type  = "KEY_AND_VALUE"
      value = var.environment
    }
  }
}
