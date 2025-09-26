# Deploying a Simple App on ECS with Fargate & Terraform using AWS Community Modules

Amazon Elastic Container Service (ECS) makes it easy to run containerized applications on AWS without managing servers. With AWS Fargate and Fargate Spot, you can run workloads in a serverless fashion while optimizing costs.

In this guide, we’ll use Terraform AWS Community Modules to provision the infrastructure and deploy a simple Node.js app hosted in a public Amazon ECR repository.

## Architecture

At the core, we provision a VPC with both public and private subnets across multiple Availability Zones for high availability. The ECS Cluster itself is a regional construct and does not directly reside in the VPC. Instead, the actual workloads — called ECS tasks — run inside the private subnets of our VPC. Each ECS task is deployed with security groups to control inbound and outbound traffic.

To make the application accessible to users on the internet, we use an Application Load Balancer (ALB). The ALB is deployed in the public subnets, where it can receive internet traffic. It forwards requests to a target group that points to the ECS tasks running in the private subnets. This separation of public and private networking ensures security while still allowing external access through the load balancer.

The ECS task definition specifies the Node.js container image (stored in a public Amazon ECR repository), along with CPU and memory settings. It also defines port mappings so the application can listen on port 8080. The ECS service ensures the desired number of tasks are always running, and it integrates with the ALB to register and deregister tasks dynamically.

For scalability, we configure autoscaling policies based on CPU and memory utilization. This means if the load increases, ECS will automatically launch more Fargate or Fargate Spot tasks to handle the traffic, and scale down during low demand to save costs.

## Step 1: Create VPC and ECS Cluster with Terraform
We’ll use the AWS community VPC and ECS modules.
```terraform
################################################################################
# VPC Module
################################################################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_vpn_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = var.common_tags
}
################################################################################
# ECS Cluster Module
################################################################################
module "ecs_cluster" {
  source  = "terraform-aws-modules/ecs/aws//modules/cluster"
  version = "~> 5.0"

  cluster_name = "${var.project_name}-cluster"

  # Fargate capacity providers
  fargate_capacity_providers = {
    FARGATE = {
      default_capacity_provider_strategy = {
        weight = 50
        base   = 20
      }
    }
    FARGATE_SPOT = {
      default_capacity_provider_strategy = {
        weight = 50
      }
    }
  }

  tags = var.common_tags
}
```
## Step 2: Create ECS Execution & Task Roles
We need IAM roles so ECS can pull images from ECR and write logs.

```terraform
################################################################################
# ECS Execution Role
################################################################################
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.project_name}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

################################################################################
# Additional policy for ECR public registry access
################################################################################
resource "aws_iam_role_policy" "ecs_execution_ecr_policy" {
  name = "${var.project_name}-ecs-execution-ecr-policy"
  role = aws_iam_role.ecs_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr-public:GetAuthorizationToken",
          "ecr-public:BatchCheckLayerAvailability",
          "ecr-public:GetDownloadUrlForLayer",
          "ecr-public:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

################################################################################
# ECS Task Role
################################################################################
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

################################################################################
# CloudWatch Logs Group
################################################################################
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = var.log_retention_days

  tags = var.common_tags
}
```

## Step 3: Create ALB with Target Group
The ALB will live in public subnets and route traffic to ECS tasks running in private subnets.
```terraform
################################################################################
# Security Group for ALB
################################################################################
resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-alb"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-alb-sg"
  })
}
################################################################################
# Application Load Balancer
################################################################################
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = false

  tags = var.common_tags
}
################################################################################
# Target Group
################################################################################
resource "aws_lb_target_group" "ecs_tg" {
  name        = "${var.project_name}-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = var.common_tags
}
################################################################################
# ALB Listener
################################################################################
resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_tg.arn
  }

  tags = var.common_tags
}
```

## Step 4: ECS Task Definition with Node.js Image
We’ll use a public ECR image of our Node.js app.
```terraform
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
```

## Step 5: ECS Service with Autoscaling
Attach the ECS service to the ALB target group and configure autoscaling.
```terraform
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

```

## Accessing the Application
Once deployed, Terraform will output the ALB DNS name. Open it in your browser:

![alt text](/images/nodejsapp.png)

Service updated to have 10 tasks:

![alt text](/images/service_update.png)

ALB target group showing 10 IP addresse:

![alt text](/images/alb-target-group.png)


## Cleanup
When finished, always clean up to avoid unnecessary costs:
```bash
terraform destory
```

## Conclusion
We successfully deployed a Node.js application to ECS with Fargate and Fargate Spot using Terraform community modules.
This setup ensures:

- Scalability with autoscaling policies
- Cost efficiency with Fargate Spot
- Security by running tasks in private subnets behind an ALB

Using Terraform makes the process repeatable, modular, and version-controlled.

## References

- [My GitHub Repo](https://github.com/chinmayto/terraform-aws-ecs)
- [Terraform AWS VPC Module](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest)
- [Terraform AWS ECS Module](https://registry.terraform.io/modules/terraform-aws-modules/ecs/aws/latest)
- [Amazon ECS Documentation](https://docs.aws.amazon.com/ecs/)