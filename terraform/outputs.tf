output "alb_dns" {
  description = "URL publique de l'ALB — point d'entrée de l'API"
  value       = aws_lb.main.dns_name
}

output "ecr_go_proxy_url" {
  description = "URL du registry ECR pour l'image Go Proxy"
  value       = aws_ecr_repository.go_proxy.repository_url
}

output "ecr_fastapi_url" {
  description = "URL du registry ECR pour l'image FastAPI"
  value       = aws_ecr_repository.fastapi.repository_url
}
