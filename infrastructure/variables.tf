variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "CT-ECS"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "private_subnets" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnets" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "ecr_repository_url" {
  description = "ECR repository URL for the Node.js app"
  type        = string
  default     = "public.ecr.aws/n4o6g6h8/my-ecs-nodejs-app:latest"
}

variable "app_port" {
  description = "Port on which the application runs"
  type        = number
  default     = 8080
}

variable "common_tags" {
  description = "Common tags to be applied to all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "nodejs-app"
    ManagedBy   = "terraform"
  }
}
#####
###########################################################################
# Auto Scaling Variables
################################################################################

variable "min_capacity" {
  description = "Minimum number of tasks"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum number of tasks"
  type        = number
  default     = 10
}

variable "cpu_target_value" {
  description = "Target CPU utilization percentage for auto scaling"
  type        = number
  default     = 70
}

variable "memory_target_value" {
  description = "Target memory utilization percentage for auto scaling"
  type        = number
  default     = 80
}

variable "requests_per_target" {
  description = "Target number of requests per target for auto scaling"
  type        = number
  default     = 1000
}

variable "scale_in_cooldown" {
  description = "Cooldown period (in seconds) for scale in operations"
  type        = number
  default     = 300
}

variable "scale_out_cooldown" {
  description = "Cooldown period (in seconds) for scale out operations"
  type        = number
  default     = 300
} #########
#######################################################################
# Task Definition Variables
################################################################################

variable "task_cpu" {
  description = "CPU units for the task (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Memory (MB) for the task"
  type        = number
  default     = 512
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}