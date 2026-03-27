// environments/prod/variables.tf
variable "aws_region" {
  description = "AWS region for the production infrastructure."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name used in tags and resource names."
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project name prefix for shared resources."
  type        = string
  default     = "rp"
}

variable "key_name" {
  description = "Optional EC2 key pair name. Leave null if you only plan to use SSM Session Manager."
  type        = string
  default     = null
}

variable "ssh_cidr_blocks" {
  description = "Optional CIDR blocks allowed to reach port 22. Leave empty to disable SSH ingress."
  type        = list(string)
  default     = []
}

variable "hermes_domain_name" {
  description = "Public domain name for the Hermes API."
  type        = string
}

variable "hermes_codedeploy_artifact_bucket" {
  description = "Existing S3 bucket used to store Hermes CodeDeploy revision bundles."
  type        = string
  default     = "rp-hermes-codedeploy-artifacts"
}

variable "hermes_letsencrypt_email" {
  description = "Email address used to register and renew the Hermes API Let's Encrypt certificate."
  type        = string
  default     = ""
}

# variable "rp_api_domain_name" {
#   description = "Public domain name for the RP API."
#   type        = string
# }
