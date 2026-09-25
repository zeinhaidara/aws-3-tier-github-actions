output "load_balancer_arn" {
  value = aws_lb.this.arn
}

output "load_balancer_dns_name" {
  value = aws_lb.this.dns_name
}

output "load_balancer_zone_id" {
  value = aws_lb.this.zone_id
}

output "load_balancer_arn_suffix" {
  value = aws_lb.this.arn_suffix
}

output "target_group_arn_suffix" {
  value = aws_lb_target_group.app.arn_suffix
}

output "target_group_arn" {
  value = aws_lb_target_group.app.arn
}

output "certificate_arn" {
  value = local.certificate_arn
}

output "application_url" {
  value = var.domain_name == "" ? "http://${aws_lb.this.dns_name}" : "https://${var.domain_name}"
}
