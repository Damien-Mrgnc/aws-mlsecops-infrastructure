output "ecr_go_proxy_url" {
  value = aws_ecr_repository.go_proxy.repository_url
}

output "ecr_fastapi_url" {
  value = aws_ecr_repository.fastapi.repository_url
}
