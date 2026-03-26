# rp-infra

Terraform scaffolding for the R|P infrastructure stack.

## Scope

This scaffold is set up for:

- one EC2 instance per API
- `t2.small` instances for both `rp-api` and Hermes
- default VPC usage to keep costs and complexity down
- host-level Nginx terminating TLS and proxying to the app container
- CodeDeploy-managed app deployments onto EC2
- stable Elastic IPs so Cloudflare DNS can point directly at each API host

Right now, the production entrypoint is intentionally wired for Hermes only. The `rp-api` module blocks are still in the Terraform files, but commented out so they can be re-enabled later.

## Current Layout

- `environments/prod`: production entrypoint
- `modules/ec2_api_service`: reusable EC2 + Nginx + CodeDeploy app module
- `.github/workflows`: R|P-owned deployment automation that builds public app repos and deploys them into the AWS environment

## Secrets / Environment Variables

This scaffold intentionally does not write application secrets into Terraform state.

Instead, both APIs are expected to keep a host-side `.env` file in the deployment directory:

- Hermes: `/home/ubuntu/hermes/.env`
- rp-api: `/home/ubuntu/rp-api/.env` when that deployment is turned back on

That matches the current operational pattern more closely than pushing secrets through Terraform. It is still less secure than a managed secret store, but it avoids the larger mistake of baking secrets into Terraform state or user data.

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
- Nginx is configured to use per-service cert paths. The bootstrap script creates a temporary self-signed cert so Nginx can start cleanly before you replace it with the real origin cert.
- Hermes now ships its own `appspec.yml` and CodeDeploy scripts, matching the `rp-api` deployment model.
- Hermes deployment automation should live here, not in the Hermes repo itself. This repo can safely hold AWS-specific GitHub Actions secrets/vars because it is the infrastructure owner.

## Hermes CI/CD

The intended Hermes deploy flow is:

1. Terraform provisions the EC2 instance, Nginx, PM2, and CodeDeploy resources
2. A GitHub Actions workflow in `rp-infra` checks out the public Hermes repo
3. The workflow builds `dist/`
4. The workflow creates a CodeDeploy bundle and uploads it to `s3://rp-hermes-codedeploy-artifacts`
5. The workflow starts a CodeDeploy deployment against the Hermes application and deployment group

The workflow needs the following repository configuration in `rp-infra`:

- Secrets:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
- Variables:
  - `AWS_REGION`
  - `HERMES_CODEDEPLOY_BUCKET`
  - `HERMES_CODEDEPLOY_APP_NAME`
  - `HERMES_CODEDEPLOY_DEPLOYMENT_GROUP`
  - `HERMES_REPOSITORY`
  - `HERMES_REF`

Suggested values:

- `AWS_REGION=us-east-2`
- `HERMES_CODEDEPLOY_BUCKET=rp-hermes-codedeploy-artifacts`
- `HERMES_CODEDEPLOY_APP_NAME=hermes-api-codedeploy-app`
- `HERMES_CODEDEPLOY_DEPLOYMENT_GROUP=hermes-api-deployment-group`
- `HERMES_REPOSITORY=HackIllinois/Hermes`
- `HERMES_REF=main`
