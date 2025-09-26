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