# AWS 3-Tier GitHub Actions

Enterprise-style three-tier application deployed on AWS EC2 and ECS/Fargate using Terraform and GitHub Actions.

This repository is being built incrementally. The first deployment target is EC2; ECS/Fargate will reuse the application afterward.

## Environments

- `dev`: active development and push-based workflow; unprotected
- `test`: promotion environment; protected
- `prod`: production environment; protected

## Planned structure

```text
app/                 # React frontend and FastAPI backend
infra/terraform/     # Bootstrap state and reusable AWS Terraform
deploy/              # EC2 and ECS deployment assets
local/               # Local development configuration
tests/               # Integration and smoke tests (later)
docs/                # Architecture and operations documentation
.github/workflows/   # CI/CD workflows, added incrementally
```

Terraform remote state will use an S3 bucket created by a separate bootstrap step before the main Terraform configuration is initialized.
