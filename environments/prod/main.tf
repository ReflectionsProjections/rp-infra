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
  codedeploy_service_role_arn = aws_iam_role.codedeploy_service.arn
  extra_tags                  = local.common_tags
}

# module "rp_api" {
#   source = "../../modules/ec2_api_service"
#
#   aws_region                  = var.aws_region
#   environment                 = var.environment
#   service_name                = "rp-api"
#   domain_name                 = var.rp_api_domain_name
#   app_port                    = 3000
#   deployment_path             = "/home/ubuntu/rp-api"
#   healthcheck_path            = "/status"
#   instance_type               = "t2.small"
#   key_name                    = var.key_name
#   ssh_cidr_blocks             = var.ssh_cidr_blocks
#   codedeploy_service_role_arn = aws_iam_role.codedeploy_service.arn
#   extra_tags                  = local.common_tags
# }
