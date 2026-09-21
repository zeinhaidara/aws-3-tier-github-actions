output "state_bucket_name" {
  description = "S3 bucket name for the main Terraform backend."
  value       = aws_s3_bucket.terraform_state.bucket
}

output "state_bucket_region" {
  description = "AWS region containing the Terraform state bucket."
  value       = var.aws_region
}
