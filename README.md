# AWS 3-Tier Application with Terraform and GitHub Actions

This repository demonstrates a repeatable AWS deployment for a FastAPI/MySQL application using EC2 Auto Scaling and ECS Fargate. Both deployments use the same tested Docker image behind an Application Load Balancer.

## Architecture

![AWS 3-tier deployment architecture](docs/diagram.png)

```text
Internet → Route 53 → ACM → Application Load Balancer
                              ├── EC2 Auto Scaling Group → FastAPI container
                              └── ECS Fargate service    → FastAPI task
                                                            ↓
                                                   Secrets Manager → RDS MySQL
```

The VPC is split into public, application, and database subnets across two Availability Zones. The ALB is public; EC2, ECS, and RDS are private.

```text
Browser → ALB:80/443 → application:8000 → RDS MySQL:3306
```

The application serves a small static frontend and API from FastAPI. `/healthz` checks process health and `/readyz` checks database readiness.

## Repository layout

```text
app/backend/                         FastAPI application, Dockerfile, tests
infra/terraform/                    Shared VPC, ALB, RDS, EC2, IAM, alarms
deploy/ecs/                          ECS cluster, Fargate task, service, logs, alarms
.github/workflows/                  CI, image publication, deployment, load testing
docs/                                Architecture and presentation material
```

## Branches and environments

The project uses a branch-based, multi-environment CI/CD model:

- Feature branches are validated through pull requests into `main`.
- `main` is the deployable branch.
- Terraform supports `dev`, `test`, and `prod`.
- Infrastructure mutations are restricted to `main`.
- The deployment workflow is manually dispatched with a target (`networking`, `ec2`, or `ecs`), environment, and operation (`plan`, `apply`, or `destroy`).

## CI/CD and immutable images

`CI - Quality and Security` runs linting, pytest coverage, Terraform validation, Checkov, Trivy filesystem and secret scans, Docker health testing, image scanning, SBOM generation, and SonarQube analysis.

After successful CI on `main`, `Publish - Application Image` publishes the exact tested image to ECR as:

```text
sha-<commit-sha>
```

ECR uses immutable tags and scan-on-push. A lifecycle policy retains the 20 newest `sha-*` images. The CD workflow resolves the newest published immutable image and deploys that tag through Terraform.

Normal deployment order:

1. Bootstrap the Terraform state backend.
2. Apply `networking`.
3. Publish an image from `main`.
4. Apply `ec2` and/or `ecs` for the selected environment.
5. Run the HTTPS smoke test.

## Security model

- GitHub Actions uses OIDC; long-lived AWS keys are not stored in GitHub.
- RDS credentials are managed by Secrets Manager.
- EC2 and ECS use IAM roles to retrieve the secret and pull from ECR.
- The ALB security group accepts public HTTP/HTTPS traffic.
- The application security group accepts port `8000` only from the ALB security group.
- The database security group accepts MySQL port `3306` only from the application security group.
- RDS is private and encrypted; EC2 requires IMDSv2.

Security-group definitions are in [infra/terraform/modules/security-groups/main.tf](infra/terraform/modules/security-groups/main.tf).

## Observability

CloudWatch collects:

```text
/cloudbatch818/zein/<environment>/app   EC2 container logs
/cloudbatch818/zein/<environment>/ecs   ECS container logs
```

Application logs are retained for seven days. RDS exports `error`, `general`, and `slowquery` logs. Terraform defines alarms for ALB target 5xx responses, ALB p95 latency above one second, high EC2 CPU, high ECS CPU, and ECS running tasks below the desired count. ECS Container Insights is enabled.

The alarms currently have no SNS actions, so they monitor state but do not send email or Slack notifications.

## Rollback and recovery

- ECS has a deployment circuit breaker with rollback enabled.
- EC2 can be manually redeployed with a previous immutable `sha-*` image.
- Terraform changes are reviewed through plans; Terraform does not automatically roll back failed infrastructure changes.
- The current CD workflow selects the newest image automatically. An explicit `image_tag` input would improve controlled rollback.

## Cleanup

Destroy in reverse dependency order:

```text
ecs → ec2 → networking
```

Run and review a destroy plan before applying. Keep the bootstrap state bucket until all dependent states are removed. Confirm that no other environment uses the shared networking stack before destroying `networking`.

## Demo setup

Create a public Route 53 hosted zone and configure the `dev` GitHub Environment with values similar to:

```text
HOSTED_ZONE_NAME=example.com
EC2_DOMAIN_NAME=ec2-dev.example.com
ECS_DOMAIN_NAME=ecs-dev.example.com
ENABLE_NAT_GATEWAY=true
```

Keep AWS role, state bucket, region, subnet, instance, and domain values in GitHub configuration rather than committing them. For the load test, set `MIN_SIZE=1` and `MAX_SIZE=2` in `dev`, then run `Test - EC2 Load and Scaling` against an HTTPS API URL.

## Production-readiness notes

Before production use:

- Add SNS or another notification target to CloudWatch alarms.
- Add an explicit deployment image-tag input for controlled rollback.
- Review RDS backup retention, deletion protection, Multi-AZ, and final-snapshot settings.
- Review NAT Gateway cost and high-availability requirements.
- Add authentication, authorization, rate limiting, WAF rules, dashboards, and alert escalation if externally exposed.
- Pin third-party GitHub Actions to reviewed commit SHAs where required.
- Add environment approvals and least-privilege production IAM policies.

These are intentional demo-scope trade-offs and should be part of a production hardening plan.
