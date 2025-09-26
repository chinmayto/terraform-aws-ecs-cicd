################################################################################
# Security Group for ECS Service
################################################################################
resource "aws_security_group" "ecs_service" {
  name_prefix = "${var.project_name}-ecs-service"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-ecs-service-sg"
  })
}

################################################################################
# ECS Task Definition
################################################################################
resource "aws_ecs_task_definition" "nodejs_app" {
  family                   = "${var.project_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.task_cpu)
  memory                   = tostring(var.task_memory)
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "nodejs-app"
      image = var.ecr_repository_url

      portMappings = [
        {
          containerPort = var.app_port
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      environment = [
        {
          name  = "NODE_ENV"
          value = "production"
        },
        {
          name  = "PORT"
          value = tostring(var.app_port)
        }
      ]

      essential = true
    }
  ])

  tags = var.common_tags
}

################################################################################
# ECS Service
################################################################################
module "ecs_service" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 5.0"

  name        = "${var.project_name}-service"
  cluster_arn = module.ecs_cluster.arn

  # Use the separate task definition
  task_definition_arn            = aws_ecs_task_definition.nodejs_app.arn
  desired_count                  = var.min_capacity
  ignore_task_definition_changes = false
  force_new_deployment           = true
  create_task_definition         = false

  # Built-in Auto Scaling
  autoscaling_min_capacity = var.min_capacity
  autoscaling_max_capacity = var.max_capacity

  autoscaling_policies = {
    cpu = {
      policy_type = "TargetTrackingScaling"
      target_tracking_scaling_policy_configuration = {
        predefined_metric_specification = {
          predefined_metric_type = "ECSServiceAverageCPUUtilization"
        }
        target_value       = var.cpu_target_value
        scale_in_cooldown  = var.scale_in_cooldown
        scale_out_cooldown = var.scale_out_cooldown
      }
    }
    memory = {
      policy_type = "TargetTrackingScaling"
      target_tracking_scaling_policy_configuration = {
        predefined_metric_specification = {
          predefined_metric_type = "ECSServiceAverageMemoryUtilization"
        }
        target_value       = var.memory_target_value
        scale_in_cooldown  = var.scale_in_cooldown
        scale_out_cooldown = var.scale_out_cooldown
      }
    }
  }

  load_balancer = {
    service = {
      target_group_arn = aws_lb_target_group.ecs_tg.arn
      container_name   = "nodejs-app"
      container_port   = var.app_port
    }
  }

  subnet_ids = module.vpc.private_subnets
  security_group_rules = {
    alb_ingress = {
      type                     = "ingress"
      from_port                = var.app_port
      to_port                  = var.app_port
      protocol                 = "tcp"
      description              = "Service port"
      source_security_group_id = aws_security_group.alb.id
    }
    egress_all = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  service_tags = var.common_tags
}
