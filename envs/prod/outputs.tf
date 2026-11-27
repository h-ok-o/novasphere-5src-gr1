output "alb_dns_name" {
  description = "Nom DNS de l'ALB."
  value       = module.web.alb_dns_name
}

output "vpc_id" {
  description = "ID du VPC."
  value       = module.vpc.vpc_id
}
