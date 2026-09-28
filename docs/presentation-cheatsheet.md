# AWS 3-Tier Application Deployment

## Demo purpose

This lab demonstrates an automated AWS deployment of a FastAPI/MySQL application using two compute models:

- EC2 instances managed by an Auto Scaling Group.
- ECS Fargate tasks managed by an ECS service.

Both deployments use the same container image and connect to the same private RDS MySQL database.

## Architecture summary

```text
Route 53 → ACM certificate → HTTPS Application Load Balancer
                                  ├─ EC2 Auto Scaling Group → FastAPI container
                                  └─ ECS Fargate service → FastAPI task
                                                        ↓
                                      Secrets Manager → RDS MySQL
```

The `dev` environment is the demonstration environment. The public endpoints are:

```text
https://ec2-dev.cloudbatch818.click/healthz
https://ecs-dev.cloudbatch818.click/healthz
```

## Demonstration narrative

### 1. Infrastructure as Code

Terraform provisions the VPC, public and private subnets, NAT gateway, route tables, security groups, ECR repository, remote state bucket, RDS, Application Load Balancers, ACM certificates, Route 53 records, EC2/ASG resources, ECS/Fargate resources, CloudWatch logs, alarms, and scaling policies.

The infrastructure is repeatable and environment-aware through variables for `dev`, `test`, and `prod`.

### 2. CI quality and security

The `CI - Quality and Security` workflow runs on pull requests and pushes to `main`.

Its stages are:

1. Ruff linting and pytest coverage.
2. Terraform formatting and validation.
3. Checkov infrastructure security scanning.
4. Trivy filesystem vulnerability, misconfiguration, and secret scanning.
5. Docker image build and `/healthz` container smoke test.
6. Trivy image scanning and SBOM generation.
7. SonarQube analysis using the coverage artifact.

The image is not published until the tested and scanned build succeeds.

### 3. Image publication

`Publish - Application Image` runs after successful CI on `main`. It downloads the exact image artifact produced by CI and publishes it to ECR with an immutable tag:

```text
sha-<commit-sha>
```

This connects the source commit, tested image, and deployed application.

### 4. Infrastructure deployment

`CD - Infrastructure` is manually dispatched with a target and operation:

- `networking`: shared VPC and networking state.
- `ec2`: RDS, ALB, ACM/Route 53, launch template, ASG, and EC2 host.
- `ecs`: ECS cluster, Fargate task definition, service, ALB, and logs.

The normal sequence is `plan`, review, then `apply`. Destruction is performed in reverse dependency order: ECS, EC2, then networking.

### 5. EC2 deployment model

Terraform creates a launch template and Auto Scaling Group. EC2 user data installs Docker, authenticates to ECR, pulls the immutable application image, and starts the container.

The ALB checks `/healthz`. The ASG uses ELB health checks and replaces instances that fail the load balancer health check.

### 6. ECS deployment model

Terraform creates an ECS Fargate task definition containing the image URI, port mapping, environment variables, logging configuration, and container health check.

The ECS service maintains the desired task count, replaces unhealthy tasks, connects tasks to the ALB target group, and uses a deployment circuit breaker for failed rollouts.

ECS is operationally simpler because AWS manages the host operating system, Docker runtime, task placement, and task replacement.

### 7. Database and security flow

The application in both EC2 and ECS connects to the same private RDS MySQL instance.

- Credentials are stored in Secrets Manager.
- The EC2 instance role or ECS task role retrieves the secret.
- The database security group allows MySQL traffic only from the application security group.
- Internet traffic enters through the ALB, not directly to the application.
- GitHub Actions uses OIDC instead of long-lived AWS access keys.

## CloudWatch demonstration

Focus on alarms beginning with `cloudbatch818-zein-dev-`. Older names such as `chikwex-*` and `aws-3tier-*` belong to previous deployments.

Important signals:

- `ec2-cpu-high`: EC2 CPU saturation.
- `app-cpu-high`: ASG application CPU.
- `alb-latency`: ALB target response time.
- `alb-5xx`: target or application errors.
- `unhealthy-targets`: failed ALB health checks.
- `TargetTracking-...app-asg...`: ASG target tracking and capacity decisions.
- `ecs-service-cpu-high`: ECS service CPU utilization.
- `ecs-running-tasks-low`: ECS task availability.
- `ecs-unhealthy-targets`: ECS target health.

Relevant log groups:

```text
/cloudbatch818/zein/dev/app
/cloudbatch818/zein/dev/ecs
```

`OK` means the metric is below the alarm threshold. `In alarm` means the condition is currently true. An alarm with no actions provides monitoring but does not send notifications. A target-tracking alarm may enter an alarm state as part of scale-out or scale-in behavior.

## Load and scaling demonstration

The load generator is ApacheBench (`ab`), installed by `.github/workflows/load-test.yml` through the `apache2-utils` package.

The workflow validates the HTTPS URL, records ASG capacity before the test, sends sustained traffic to the EC2 ALB, records ApacheBench results, captures scaling activity, and uploads the evidence as a GitHub Actions artifact.

For this demonstration, the EC2 target-tracking policy targets 20% average CPU, bounded by the environment’s `MIN_SIZE` and `MAX_SIZE` values. Restore the production-style 60% target after the demo.

## Final evidence checklist

- CI workflow completed successfully.
- ECR image publication completed successfully.
- EC2 and ECS CD plan/apply completed successfully.
- Both `/healthz` HTTPS endpoints return `{"status":"ok"}`.
- Route 53 resolves both application subdomains.
- HTTP traffic redirects to HTTPS.
- CloudWatch shows application logs and infrastructure metrics.
- The load-test artifact contains performance results and ASG scaling activity.
