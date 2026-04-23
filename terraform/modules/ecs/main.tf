# ── ECR ───────────────────────────────────────────────────────────────────────

resource "aws_ecr_repository" "go_proxy" {
  name = "${var.project_name}-go-proxy"
  # IMMUTABLE : empêche l'écrasement d'un tag existant (CKV_AWS_51)
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  # KMS désactivé : utilise le chiffrement AES-256 par défaut d'AWS, suffisant pour démo
  #checkov:skip=CKV_AWS_136:Chiffrement AES-256 par défaut activé, KMS CMK ajouté en prod
}

resource "aws_ecr_repository" "fastapi" {
  name                 = "${var.project_name}-fastapi"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  #checkov:skip=CKV_AWS_136:Chiffrement AES-256 par défaut activé, KMS CMK ajouté en prod
}

# ── ECS Cluster ───────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  # Container Insights : métriques CPU/mémoire par container dans CloudWatch (CKV_AWS_65)
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# ── IAM Roles ─────────────────────────────────────────────────────────────────

# Rôle d'exécution — permet à ECS de puller les images ECR et écrire les logs CloudWatch
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-ecs-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Rôle de la task — moindre privilège : DynamoDB + Secrets Manager uniquement
resource "aws_iam_role" "ecs_task" {
  name = "${var.project_name}-ecs-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_policy" {
  name = "${var.project_name}-task-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Query"]
        Resource = [
          var.dynamodb_table_arn,
          "${var.dynamodb_table_arn}/index/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [var.openai_secret_arn, var.api_keys_secret_arn]
      }
    ]
  })
}

# ── CloudWatch Log Groups ─────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "fastapi" {
  name = "/ecs/${var.project_name}/fastapi"
  # 365 jours minimum requis par Checkov (CKV_AWS_338)
  retention_in_days = 365
  # KMS désactivé : chiffrement AES-256 par défaut, KMS CMK ajouté en prod
  #checkov:skip=CKV_AWS_158:Chiffrement AES-256 par défaut activé, KMS CMK ajouté en prod
}

resource "aws_cloudwatch_log_group" "go_proxy" {
  name              = "/ecs/${var.project_name}/go-proxy"
  retention_in_days = 365
  #checkov:skip=CKV_AWS_158:Chiffrement AES-256 par défaut activé, KMS CMK ajouté en prod
}

# ── ECS Task Definition ───────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "main" {
  family                   = "${var.project_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "fastapi"
      image     = "${aws_ecr_repository.fastapi.repository_url}:latest"
      essential = true
      # Système de fichiers racine en lecture seule (CKV_AWS_336)
      readonlyRootFilesystem = true
      portMappings = [{ containerPort = 8000 }]
      environment = [
        { name = "AWS_REGION",     value = var.aws_region },
        { name = "DYNAMODB_TABLE", value = var.dynamodb_table_name },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project_name}/fastapi"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    },
    {
      name      = "go-proxy"
      image     = "${aws_ecr_repository.go_proxy.repository_url}:latest"
      essential = true
      readonlyRootFilesystem = true
      portMappings = [{ containerPort = 8080 }]
      environment = [
        { name = "FASTAPI_URL",    value = "http://localhost:8000" },
        { name = "DYNAMODB_TABLE", value = var.dynamodb_table_name },
        { name = "PROXY_PORT",     value = "8080" },
      ]
      dependsOn = [{ containerName = "fastapi", condition = "START" }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project_name}/go-proxy"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# ── ECS Service ───────────────────────────────────────────────────────────────

resource "aws_ecs_service" "main" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_tasks_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "go-proxy"
    container_port   = 8080
  }
}
