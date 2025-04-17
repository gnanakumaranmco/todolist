provider "aws" {
  region = "ap-south-1"
}

# ECR
resource "aws_ecr_repository" "web_app_repo" {
  name = "static-web-app-repo"
}

# ECS Cluster
resource "aws_ecs_cluster" "web_app_cluster" {
  name = "static-web-app-cluster"
}

# Load Balancer
resource "aws_lb" "web_app_lb" {
  name               = "web-app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["sg-0ea8212f0856ff058"]
  subnets            = ["subnet-0fcc7d7a34648475b", "subnet-050c56435de4e4513"]
}

# Target Group
resource "aws_lb_target_group" "web_app_tg" {
  name        = "web-app-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = "vpc-0946d53b00481c27c"
  target_type = "ip"

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

# HTTPS Listener with ACM
resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_lb.web_app_lb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:acm:ap-south-1:522814733729:certificate/71f977c6-d961-4fbd-b5c1-c151c6e09334"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_app_tg.arn
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task
resource "aws_ecs_task_definition" "web_app_task" {
  family                   = "static-web-app-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name      = "web-container"
    image     = "${aws_ecr_repository.web_app_repo.repository_url}:latest"
    portMappings = [{
      containerPort = 80
      hostPort      = 80
    }]
  }])
}

# ECS Service
resource "aws_ecs_service" "web_app_service" {
  name            = "static-web-app-service"
  cluster         = aws_ecs_cluster.web_app_cluster.id
  task_definition = aws_ecs_task_definition.web_app_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = ["subnet-0fcc7d7a34648475b", "subnet-050c56435de4e4513"]
    assign_public_ip = true
    security_groups  = ["sg-0ea8212f0856ff058"]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web_app_tg.arn
    container_name   = "web-container"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.https_listener]
}

# Route 53 Record: app.nosmoking.sbs => ECS Load Balancer
resource "aws_route53_record" "ecs_lb_dns" {
  zone_id = "Z0613656MPUJP2OYYPEL"
  name    = "app.nosmoking.sbs"
  type    = "A"

  alias {
    name                   = aws_lb.web_app_lb.dns_name
    zone_id                = aws_lb.web_app_lb.zone_id
    evaluate_target_health = true
  }
}
