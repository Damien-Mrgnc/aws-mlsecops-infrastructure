output "alb_dns" {
  description = "URL publique de l'ALB — point d'entrée de l'API"
  value       = module.networking.alb_dns_name
}

output "ecr_go_proxy_url" {
  description = "URL du registry ECR pour l'image Go Proxy"
  value       = module.ecs.ecr_go_proxy_url
}

output "ecr_fastapi_url" {
  description = "URL du registry ECR pour l'image FastAPI"
  value       = module.ecs.ecr_fastapi_url
}
