# rp-infra

Terraform scaffolding for the R|P infrastructure stack.

## Scope

This scaffold is set up for:

- one EC2 instance per API
- a `t2.small` instance for Hermes
- a `t2.micro` instance for the Terraform-managed RP API host
- default VPC usage to keep costs and complexity down
- host-level Nginx terminating TLS and proxying to the app container
- CodeDeploy-managed app deployments onto EC2
- stable Elastic IPs so Cloudflare DNS can point directly at each API host

The production entrypoint now wires up:

- Hermes on its current host
- an `rp-api` host, reachable at the temporary domain `api-staging.reflectionsprojections.org` until cutover

The existing production `api.reflectionsprojections.org` box is still manually provisioned and remains outside Terraform until cutover.

## Current Layout

- `environments/prod`: production entrypoint
- `modules/ec2_api_service`: reusable EC2 + Nginx + CodeDeploy app module
- `.github/workflows`: R|P-owned deployment automation that builds public app repos and deploys them into the AWS environment

## Secrets / Environment Variables

This scaffold intentionally does not write application secrets into Terraform state.

- Hermes keeps a manually managed host-side `.env` file at `/home/ubuntu/hermes/.env`.
- rp-api reads its secrets from AWS Secrets Manager at deploy time. Terraform creates two empty secret shells (`rp-api/prod/env` and `rp-api/prod/firebase-admin-cert`) and grants the instance role `secretsmanager:GetSecretValue` on them. Load the values manually in the AWS console as plaintext: the full `.env` file content in the first, the Firebase service account JSON in the second. A CodeDeploy hook (`services/api/scripts/load_env.sh` in rp-monorepo) fetches both on every deployment and writes `/home/ubuntu/rp-api/.env` and `/home/ubuntu/rp-api/firebase-admin-cert.json`.

Terraform never reads the secret values, so they stay out of the state file.

The EC2 module can also install a manual Supabase backup helper script without managing any scheduler or secret material. When enabled, the script is written to `/usr/local/bin/supabase_backups.sh` and is expected to read its credentials and bucket settings from a host-created env file such as `/etc/rp-api/supabase-backup.env`.

## Terraform Usage

1. Copy `environments/prod/terraform.tfvars.example` to a local `terraform.tfvars`
2. Fill in the domain names and, if needed, an EC2 key pair name
3. From `environments/prod`, run:

```bash
terraform init
terraform plan
terraform apply
```

## Notes

- Cloudflare DNS is not yet managed in this scaffold. Terraform outputs the Elastic IPs you can point A records at.
- Nginx is configured to use stable per-service cert paths. The bootstrap script creates a temporary self-signed cert so Nginx can start cleanly before Certbot issues a real certificate.
- The RP API host installs the manual Supabase backup helper script, but scheduling remains entirely manual on the instance.
- Deployment automation lives here, not in the app repos themselves. This repo can safely hold AWS-specific GitHub Actions secrets/vars because it is the infrastructure owner.
- Hermes is retired: its deploy workflow has been removed, though its instance is still Terraform-managed. See the "Hermes (retired)" section below.

## Manual Supabase Backups

The shared EC2 module can optionally install a backup helper script for services that need to export a Supabase Postgres database to S3. Terraform only installs the script and its package dependencies. It does not create an env file, cron job, or timer.

To enable it for a service module:

```hcl
install_supabase_backup_script = true
supabase_backup_env_path       = "/etc/rp-api/supabase-backup.env"
```

After the instance is provisioned, create the env file manually on the host with values like:

```bash
DB_HOST=...
DB_PORT=6543
DB_USER=...
DB_NAME=postgres
DB_PASSWORD=...
S3_BUCKET=rp-api-supabase-backups
S3_PREFIX=supabase
```

Then lock it down:

```bash
sudo chmod 600 /etc/rp-api/supabase-backup.env
```

You can test the helper manually with:

```bash
sudo /usr/local/bin/supabase_backups.sh
```

If you later want recurring backups, add and remove cron entries manually on the box as needed.

## Hermes TLS

Hermes now uses host-managed Let's Encrypt certificates rather than long-lived self-signed certs or a cert copied in from Terraform.

- Set `hermes_letsencrypt_email` in `terraform.tfvars`
- Keep the DNS record for `hermes_domain_name` pointed at the instance
- The instance bootstrap will:
  - start Nginx with a temporary self-signed certificate
  - install Certbot
  - attempt `certbot certonly --nginx`
  - copy the issued certificate into the stable Nginx paths Terraform manages
  - install a Certbot renewal hook so renewals keep those paths fresh

If first-boot issuance happens before DNS is ready, you can rerun it on the box with:

```bash
sudo /usr/local/bin/hermes-api-issue-letsencrypt-cert.sh
```

After the origin has a real certificate, Cloudflare should be set to `Proxied` with SSL/TLS mode `Full (strict)`.

## Hermes (retired)

Hermes is no longer deployed. The `deploy-hermes.yml` workflow has been removed so nothing can trigger a Hermes deploy. The Terraform module for the Hermes instance is still in `environments/prod` and the instance is still running; remove the `hermes_api` module (and the Hermes statements in the deployer IAM policy) and apply when you are ready to decommission it.

## RP API CI/CD

The intended RP API deploy flow is:

1. Terraform provisions the EC2 instance, Nginx, PM2, CodeDeploy resources, and the manual backup helper script
2. A GitHub Actions workflow in `rp-infra` checks out the `rp-monorepo` repository
3. The workflow packages the contents of `services/api` as the CodeDeploy bundle root
4. The workflow uploads the zip to the RP API artifact bucket
5. The workflow starts a CodeDeploy deployment against the RP API application and deployment group

The workflow needs the following repository configuration in `rp-infra`:

- Secrets:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
  - `RP_API_REPOSITORY_TOKEN`
- Variables:
  - `AWS_REGION`
  - `RP_API_CODEDEPLOY_BUCKET`
  - `RP_API_CODEDEPLOY_APP_NAME`
  - `RP_API_CODEDEPLOY_DEPLOYMENT_GROUP`
  - `RP_API_REPOSITORY`
  - `RP_API_REF`

Suggested values:

- `AWS_REGION=us-east-2`
- `RP_API_CODEDEPLOY_BUCKET=rp-api-codedeploy-artifacts`
- `RP_API_CODEDEPLOY_APP_NAME=rp-api-codedeploy-app`
- `RP_API_CODEDEPLOY_DEPLOYMENT_GROUP=rp-api-deployment-group`
- `RP_API_REPOSITORY=ReflectionsProjections/rp-monorepo`
- `RP_API_REF=main`

If `rp-monorepo` is private, `RP_API_REPOSITORY_TOKEN` should be a token that can read that repository.
