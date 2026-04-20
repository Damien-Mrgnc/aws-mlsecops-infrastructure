variable "project_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "private_subnet_ids" {
  description = "Subnets privés pour les tasks ECS"
  type        = list(string)
}

variable "ecs_tasks_sg_id" {
  description = "Security group des tasks ECS"
  type        = string
}

variable "target_group_arn" {
  description = "ARN du target group ALB"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN de la table DynamoDB d'audit"
  type        = string
}

variable "dynamodb_table_name" {
  description = "Nom de la table DynamoDB d'audit"
  type        = string
}

variable "openai_secret_arn" {
  description = "ARN du secret OpenAI dans Secrets Manager"
  type        = string
}

variable "api_keys_secret_arn" {
  description = "ARN du secret des clés API dans Secrets Manager"
  type        = string
}
