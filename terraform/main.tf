terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Backend S3 à activer quand le compte AWS est prêt
  # backend "s3" {
  #   bucket = "mlsecops-tfstate"
  #   key    = "prod/terraform.tfstate"
  #   region = "eu-west-3"
  # }
}

provider "aws" {
  region = var.aws_region
}

module "networking" {
  source       = "./modules/networking"
  project_name = var.project_name
  aws_region   = var.aws_region
}

module "dynamodb" {
  source       = "./modules/dynamodb"
  project_name = var.project_name
}

module "secrets" {
  source         = "./modules/secrets"
  project_name   = var.project_name
  openai_api_key = var.openai_api_key
}

module "ecs" {
  source       = "./modules/ecs"
  project_name = var.project_name
  aws_region   = var.aws_region

  private_subnet_ids  = module.networking.private_subnet_ids
  ecs_tasks_sg_id     = module.networking.ecs_tasks_sg_id
  target_group_arn    = module.networking.target_group_arn

  dynamodb_table_arn  = module.dynamodb.table_arn
  dynamodb_table_name = module.dynamodb.table_name

  openai_secret_arn   = module.secrets.openai_key_arn
  api_keys_secret_arn = module.secrets.api_keys_arn
}

module "waf" {
  source       = "./modules/waf"
  project_name = var.project_name
  alb_arn      = module.networking.alb_arn
}
