variable "project_name" {
  type = string
}

variable "alb_arn" {
  description = "ARN de l'ALB auquel associer le WAF"
  type        = string
}
