# Terraform state bootstrap

This configuration creates the S3 bucket used by the main Terraform configuration. It must run before the main configuration is initialized with an S3 backend.

Run through the GitHub Actions `Terraform bootstrap` workflow. It authenticates with the configured GitHub OIDC role and uses the runner's temporary local state only to create the remote state bucket.

The main Terraform configuration must use the resulting bucket through `terraform init -backend-config`. Do not commit generated state, plans, or `.terraform` files.
