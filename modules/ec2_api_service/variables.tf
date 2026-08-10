//ec2_api_service/variables.tf
variable "aws_region" {
  description = "AWS region used for bootstrapping region-specific services like CodeDeploy."
  type        = string
}

variable "environment" {
  description = "Environment name used in resource tags and CodeDeploy targeting."
  type        = string
}

variable "service_name" {
  description = "Short service identifier, used in names and tags."
  type        = string
}

variable "domain_name" {
  description = "Public DNS name that Nginx should answer for."
  type        = string
}

variable "app_port" {
  description = "Internal application port exposed on localhost and proxied by Nginx."
  type        = number
}

variable "deployment_path" {
  description = "CodeDeploy destination path on the instance."
  type        = string
}

variable "healthcheck_path" {
  description = "HTTP path Nginx and deployment checks should use."
  type        = string
  default     = "/"
}

variable "instance_type" {
  description = "EC2 instance type for this service."
  type        = string
  default     = "t2.small"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB. The default matches the Ubuntu AMI's stock 8 GB so existing instances see no diff; raise it for hosts that build on-box."
  type        = number
  default     = 8
}

variable "key_name" {
  description = "Optional EC2 key pair name."
  type        = string
  default     = null
}

variable "ssh_cidr_blocks" {
  description = "Optional CIDR blocks allowed to reach port 22."
  type        = list(string)
  default     = []
}

variable "codedeploy_service_role_arn" {
  description = "IAM role ARN used by the CodeDeploy deployment group."
  type        = string
}

variable "tls_certificate_path" {
  description = "Path on the EC2 host where the certificate for Nginx should live."
  type        = string
  default     = ""
}

variable "tls_private_key_path" {
  description = "Path on the EC2 host where the private key for Nginx should live."
  type        = string
  default     = ""
}

variable "use_letsencrypt" {
  description = "Whether to install Certbot and attempt to issue a Let's Encrypt certificate for the service domain."
  type        = bool
  default     = false
}

variable "letsencrypt_email" {
  description = "Email address used for Let's Encrypt registration. Required when use_letsencrypt is true."
  type        = string
  default     = ""
}

variable "install_supabase_backup_script" {
  description = "Whether to install the manual Supabase backup helper script on the instance."
  type        = bool
  default     = false
}

variable "supabase_backup_env_path" {
  description = "Path to the manual env file consumed by the Supabase backup helper script."
  type        = string
  default     = "/etc/rp-api/supabase-backup.env"
}

variable "secretsmanager_secret_arns" {
  description = "Secrets Manager secret ARNs the instance role may read. Deploy hook scripts fetch these to build the app .env file."
  type        = list(string)
  default     = []
}

variable "install_cloudwatch_agent" {
  description = "Whether to install the CloudWatch agent on the instance. Required when deploy scripts load a CloudWatch agent config."
  type        = bool
  default     = false
}

variable "create_codedeploy_artifact_bucket" {
  description = "Whether to create the S3 bucket that CI uploads CodeDeploy revision bundles to."
  type        = bool
  default     = false
}

variable "codedeploy_artifact_bucket_name" {
  description = "Name of the CodeDeploy artifact bucket to create. Required when create_codedeploy_artifact_bucket is true."
  type        = string
  default     = ""
}

variable "supabase_backup_bucket" {
  description = "Optional S3 bucket name the Supabase backup script uploads to. Grants the instance role s3:PutObject on it."
  type        = string
  default     = ""
}

variable "extra_tags" {
  description = "Additional tags applied to resources for this service."
  type        = map(string)
  default     = {}
}
