# AWS 3-Tier GitHub Actions

This `main` branch is intentionally empty except for the project bootstrap structure and this README.

Do not develop, deploy, or modify infrastructure directly on `main`. Development happens on `dev`, with promotion through `test` to `prod`.

The first deployment target is EC2. ECS/Fargate will reuse the application afterward.

## Environments

- `dev`: active development and integration branch; unprotected for this lab
- `test`: protected validation environment
- `prod`: protected production environment

## Branch flow

```text
feature/* → dev → test → prod
```

`main` is documentation-only and must remain untouched after bootstrap.

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
