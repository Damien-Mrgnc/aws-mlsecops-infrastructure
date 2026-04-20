variable "project_name" {
  description = "Préfixe utilisé sur les secrets"
  type        = string
}

variable "openai_api_key" {
  description = "Clé API OpenAI à stocker dans Secrets Manager"
  type        = string
  sensitive   = true
}
