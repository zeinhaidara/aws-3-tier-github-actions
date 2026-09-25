# ECS deployment

The ECS deployment runs the FastAPI image on Fargate in private application subnets. An internet-facing Application Load Balancer routes traffic to the service, and logs are sent to CloudWatch Logs.

For the dev demo, set these GitHub Environment variables:

```text
HOSTED_ZONE_NAME=example.com
ECS_DOMAIN_NAME=ecs-dev.example.com
```

Terraform creates the ACM certificate, validates it through Route 53, creates the DNS alias, and redirects HTTP to HTTPS.

```text
https://ecs-dev.example.com/healthz
https://ecs-dev.example.com/readyz
```

Use immutable ECR image tags for repeatable deployments.
