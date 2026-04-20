output "openai_key_arn" {
  value = aws_secretsmanager_secret.openai_key.arn
}

output "api_keys_arn" {
  value = aws_secretsmanager_secret.api_keys.arn
}
