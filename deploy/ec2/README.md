# EC2 deployment

The EC2 deployment provisions an Auto Scaling Group in private application subnets. Instances pull the application image from ECR and connect to private RDS MySQL. Public traffic enters through an Application Load Balancer.

For the dev demo, set these GitHub Environment variables:

```text
HOSTED_ZONE_NAME=example.com
EC2_DOMAIN_NAME=ec2-dev.example.com
```

Terraform creates the ACM certificate, validates it through Route 53, creates the DNS alias, and redirects HTTP to HTTPS.

```text
https://ec2-dev.example.com/healthz
https://ec2-dev.example.com/readyz
```
