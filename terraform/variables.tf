variable "aws_region" {
  description = "Région AWS cible"
  default     = "eu-west-3"
}

variable "project_name" {
  description = "Nom du projet — utilisé comme préfixe sur toutes les ressources AWS"
  default     = "mlsecops"
}

variable "environment" {
  description = "Environnement cible"
  default     = "prod"
}

variable "openai_api_key" {
  description = "Clé API OpenAI — sera stockée dans Secrets Manager, jamais en clair dans le code"
  sensitive   = true
}
