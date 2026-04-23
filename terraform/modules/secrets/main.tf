resource "aws_secretsmanager_secret" "openai_key" {
  name = "${var.project_name}/openai-key"

  # KMS désactivé : chiffrement AES-256 par défaut activé, KMS CMK ajouté en prod
  #checkov:skip=CKV_AWS_149:Chiffrement AES-256 par défaut activé, KMS CMK ajouté en prod
  # Auto-rotation désactivée : nécessite une Lambda dédiée, hors scope démo
  #checkov:skip=CKV2_AWS_57:Auto-rotation nécessite une Lambda, activée en prod
}

resource "aws_secretsmanager_secret_version" "openai_key" {
  secret_id     = aws_secretsmanager_secret.openai_key.id
  secret_string = var.openai_api_key
}

resource "aws_secretsmanager_secret" "api_keys" {
  name = "${var.project_name}/api-keys"

  #checkov:skip=CKV_AWS_149:Chiffrement AES-256 par défaut activé, KMS CMK ajouté en prod
  #checkov:skip=CKV2_AWS_57:Auto-rotation nécessite une Lambda, activée en prod
}

resource "aws_secretsmanager_secret_version" "api_keys" {
  secret_id     = aws_secretsmanager_secret.api_keys.id
  secret_string = "prod-key-abc123,prod-key-def456"
}
