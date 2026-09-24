output "cluster_name" { value = module.eks.cluster_name }
output "load_balancer_hostname" { value = try(kubernetes_service.app.status[0].load_balancer[0].ingress[0].hostname, "pending") }
