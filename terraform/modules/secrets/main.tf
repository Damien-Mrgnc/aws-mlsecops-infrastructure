resource "aws_secretsmanager_secret" "openai_key" {
  name = "${var.project_name}/openai-key"
}

resource "aws_secretsmanager_secret_version" "openai_key" {
  secret_id     = aws_secretsmanager_secret.openai_key.id
  secret_string = var.openai_api_key
}

resource "aws_secretsmanager_secret" "api_keys" {
  name = "${var.project_name}/api-keys"
}

resource "aws_secretsmanager_secret_version" "api_keys" {
  secret_id     = aws_secretsmanager_secret.api_keys.id
  secret_string = "prod-key-abc123,prod-key-def456"
}
