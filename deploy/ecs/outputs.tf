output "application_url" {
  value = "http://${aws_lb.app.dns_name}"
}

output "cluster_name" {
  value = aws_ecs_cluster.app.name
}

output "service_name" {
  value = aws_ecs_service.app.name
}
