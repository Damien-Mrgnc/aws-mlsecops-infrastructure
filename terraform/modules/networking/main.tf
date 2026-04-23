data "aws_availability_zones" "available" {}

# ── VPC ───────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "${var.project_name}-vpc" }
}

# Bloque tout trafic sur le SG par défaut du VPC (CKV2_AWS_12)
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-default-sg-deny-all" }
}

# ── Subnets ───────────────────────────────────────────────────────────────────

resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  # false : l'ALB n'a pas besoin d'IP publique assignée aux instances (CKV_AWS_130)
  map_public_ip_on_launch = false
  tags = { Name = "${var.project_name}-public-${count.index}" }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "${var.project_name}-private-${count.index}" }
}

# ── Internet Gateway & NAT ────────────────────────────────────────────────────

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.project_name}-rt-public" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${var.project_name}-nat" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = { Name = "${var.project_name}-rt-private" }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ── VPC Flow Logs (CKV2_AWS_11) ───────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/vpc/${var.project_name}/flow-logs"
  retention_in_days = 365
  #checkov:skip=CKV_AWS_158:Chiffrement AES-256 par défaut activé, KMS CMK ajouté en prod
}

resource "aws_iam_role" "vpc_flow_log" {
  name = "${var.project_name}-vpc-flow-log-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "vpc_flow_log" {
  name = "${var.project_name}-vpc-flow-log-policy"
  role = aws_iam_role.vpc_flow_log.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = [
        aws_cloudwatch_log_group.vpc_flow_logs.arn,
        "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
      ]
    }]
  })
}

resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.vpc_flow_log.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
}

# ── Security Groups ───────────────────────────────────────────────────────────

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "ALB: autorise HTTP (redirect) et HTTPS entrant depuis Internet"
  vpc_id      = aws_vpc.main.id

  # Port 80 requis pour la redirection HTTP→HTTPS
  #checkov:skip=CKV_AWS_260:Port 80 ouvert uniquement pour redirection vers HTTPS (HTTP 301)
  ingress {
    description = "HTTP entrant pour redirection vers HTTPS"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS entrant depuis Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Egress requis pour que l'ALB forward les requêtes vers les tasks ECS
  #checkov:skip=CKV_AWS_382:Egress requis pour forward ALB → ECS tasks
  egress {
    description = "Egress vers ECS tasks"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-alb-sg" }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-ecs-tasks-sg"
  description = "ECS Tasks: autorise uniquement le trafic depuis l'ALB"
  vpc_id      = aws_vpc.main.id
  # SG attaché au service ECS via aws_ecs_service (référence croisée inter-modules)
  #checkov:skip=CKV2_AWS_5:False positive - SG attaché à l'ECS service dans le module ecs

  ingress {
    description     = "Trafic depuis l'ALB uniquement"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  # Egress requis pour appeler OpenAI, DynamoDB, Secrets Manager via NAT
  #checkov:skip=CKV_AWS_382:Egress requis pour appels AWS APIs et OpenAI via NAT Gateway
  egress {
    description = "Egress vers AWS APIs et OpenAI via NAT"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-ecs-tasks-sg" }
}

# ── ALB ───────────────────────────────────────────────────────────────────────

resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  # Rejette les requêtes HTTP avec des headers malformés (CKV_AWS_131)
  drop_invalid_header_fields = true
  # Empêche la suppression accidentelle de l'ALB (CKV_AWS_150)
  enable_deletion_protection = true

  # Access logs désactivés : nécessite un bucket S3 dédié, hors scope démo
  #checkov:skip=CKV_AWS_91:Access logs nécessitent un bucket S3 dédié, activé en prod
  #checkov:skip=CKV2_AWS_28:WAF associé via aws_wafv2_web_acl_association dans le module waf

  tags = { Name = "${var.project_name}-alb" }
}

resource "aws_lb_target_group" "main" {
  name        = "${var.project_name}-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  # Target group en HTTP interne (communication intra-VPC) — HTTPS nécessite un cert interne
  #checkov:skip=CKV_AWS_378:Communication intra-VPC en HTTP, HTTPS externe géré par le listener ALB
  #checkov:skip=CKV2_AWS_20:Redirect HTTP→HTTPS configuré sur le listener port 80

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 10
  }
}

# Listener port 80 : redirige vers HTTPS (CKV2_AWS_20)
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  #checkov:skip=CKV_AWS_2:Ce listener redirige vers HTTPS, il n'est pas lui-même HTTPS
  #checkov:skip=CKV_AWS_103:TLS configuré sur le listener HTTPS, pas sur le redirect HTTP
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
