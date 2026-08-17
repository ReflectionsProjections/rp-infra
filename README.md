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

- Hermes on its current host (retired, see below)
- the `rp-api` host serving `api.reflectionsprojections.org`

The previous hand-provisioned `api.reflectionsprojections.org` box is out of rotation since the cutover and can be decommissioned once nothing on it is still needed.

## Current Layout

- `environments/prod`: production entrypoint
- `modules/ec2_api_service`: reusable EC2 + Nginx + CodeDeploy app module
- `.github/workflows`: R|P-owned deployment automation that builds public app repos and deploys them into the AWS environment

## Secrets / Environment Variables

This scaffold intentionally does not write application secrets into Terraform state.

- Hermes keeps a manually managed host-side `.env` file at `/home/ubuntu/hermes/.env`.
- rp-api reads its secrets from AWS Secrets Manager at deploy time. Terraform creates three empty secret shells (`rp-api/prod/env`, `rp-api/prod/firebase-admin-cert`, and `rp-api/prod/supabase-backup-env`) and grants the instance role `secretsmanager:GetSecretValue` on them. Load the values manually in the AWS console as plaintext: the full `.env` file content in the first, the Firebase service account JSON in the second, and the backup script's Postgres connection lines in the third. A CodeDeploy hook (`services/api/scripts/load_env.sh` in rp-monorepo) fetches the first two on every deployment and writes `/home/ubuntu/rp-api/.env` and `/home/ubuntu/rp-api/firebase-admin-cert.json`; the backup script fetches the third at runtime and writes nothing to disk.

Terraform never reads the secret values, so they stay out of the state file. No secret file on any rp-api host is created by hand.

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
- The RP API host gets postgresql-client for the Supabase backup script, which ships in the CodeDeploy bundle; scheduling remains entirely manual on the instance.
- Deployment automation lives here, not in the app repos themselves. This repo can safely hold AWS-specific GitHub Actions secrets/vars because it is the infrastructure owner.
- Hermes is retired: its deploy workflow has been removed, though its instance is still Terraform-managed. See the "Hermes (retired)" section below.

## Manual Supabase Backups

The backup script itself lives in rp-monorepo (`services/api/scripts/supabase_backups.sh`) and arrives on the host with every CodeDeploy bundle, so it never goes stale. It exports every public table to CSV and uploads to the `rp-api-supabase-backups` bucket. Terraform's part is:

- `install_supabase_backup_tools = true` on the service module installs `postgresql-client` at first boot
- `supabase_backup_bucket` grants the instance role `s3:PutObject` on the backup bucket
- the `rp-api/prod/supabase-backup-env` secret shell holds the Postgres connection values the script fetches at runtime (nothing credential-bearing is created on the host)

Load these plaintext lines into the secret (values from the Supabase dashboard's session pooler; the DB password is the database password, not the service key):

```bash
DB_HOST=...
DB_PORT=...
DB_USER=...
DB_NAME=postgres
DB_PASSWORD=...
```

Optional lines: `S3_BUCKET` (default `rp-api-supabase-backups`) and `S3_PREFIX` (default `supabase`).

Test it on the host with:

```bash
sudo /home/ubuntu/rp-api/scripts/supabase_backups.sh
```

Nothing schedules it by default. For recurring backups, add a cron entry on the box (note the `PATH` line — cron does not include `/usr/local/bin`, where the AWS CLI lives):

```
PATH=/usr/local/bin:/usr/bin:/bin
0 9 * * * root /home/ubuntu/rp-api/scripts/supabase_backups.sh >> /var/log/supabase-backup.log 2>&1
```

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

1. Terraform provisions the EC2 instance, Nginx, PM2, and the CodeDeploy resources
2. A GitHub Actions workflow in `rp-infra` checks out the `rp-monorepo` repository
3. The workflow packages the contents of `services/api` as the CodeDeploy bundle root
4. The workflow uploads the zip to the RP API artifact bucket
5. The workflow starts a CodeDeploy deployment against the RP API application and deployment group

The workflow authenticates to AWS with GitHub's OIDC provider: it assumes the
`rp-github-deployer` IAM role (defined in `environments/prod`), so there are no
long-lived AWS keys in repository secrets. The role's trust policy only accepts
workflow runs from the `main` branch of this repository.

The workflow needs the following repository configuration in `rp-infra`:

- Secrets:
  - `RP_API_REPOSITORY_TOKEN`
- Variables:
  - `AWS_REGION`
  - `AWS_DEPLOY_ROLE_ARN`
  - `RP_API_CODEDEPLOY_BUCKET`
  - `RP_API_CODEDEPLOY_APP_NAME`
  - `RP_API_CODEDEPLOY_DEPLOYMENT_GROUP`
  - `RP_API_REPOSITORY`
  - `RP_API_REF`

Suggested values:

- `AWS_REGION=us-east-2`
- `AWS_DEPLOY_ROLE_ARN` — the `github_deployer_role_arn` Terraform output
- `RP_API_CODEDEPLOY_BUCKET=rp-api-codedeploy-artifacts`
- `RP_API_CODEDEPLOY_APP_NAME=rp-api-codedeploy-app`
- `RP_API_CODEDEPLOY_DEPLOYMENT_GROUP=rp-api-deployment-group`
- `RP_API_REPOSITORY=ReflectionsProjections/rp-monorepo`
- `RP_API_REF=main`

If `rp-monorepo` is private, `RP_API_REPOSITORY_TOKEN` should be a token that can read that repository.
