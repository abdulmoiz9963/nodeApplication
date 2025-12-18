resource "aws_ecs_cluster" "main" {
  name = var.cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = var.tags
}

resource "aws_security_group" "ecs" {
  name_prefix = "ecs-sg"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 32768
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "ecs-security-group"
  })
}

resource "aws_cloudwatch_log_group" "gateway" {
  name              = "/ecs/gateway-task"
  retention_in_days = 7

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/ecs/worker-task"
  retention_in_days = 7

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "mongodb" {
  name              = "/ecs/mongodb-task"
  retention_in_days = 7

  tags = var.tags
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ECS Instance Role
resource "aws_iam_role" "ecs_instance_role" {
  name = "ecsInstanceRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_instance_role_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "ecsInstanceProfile"
  role = aws_iam_role.ecs_instance_role.name
}

# Launch Template for ECS instances
data "aws_ami" "ecs_optimized" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
}

resource "aws_launch_template" "ecs_instance" {
  name_prefix   = "ecs-instance-"
  image_id      = data.aws_ami.ecs_optimized.id
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.ecs.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${aws_ecs_cluster.main.name} >> /etc/ecs/ecs.config
    yum update -y
    yum install -y docker
    service docker start
    usermod -a -G docker ec2-user
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "ecs-instance"
    })
  }
}

# Auto Scaling Group for ECS instances
resource "aws_autoscaling_group" "ecs_asg" {
  name                = "ecs-asg"
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = []
  health_check_type   = "EC2"
  min_size            = 1
  max_size            = 3
  desired_capacity    = 2

  launch_template {
    id      = aws_launch_template.ecs_instance.id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = false
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

resource "aws_ecs_task_definition" "mongodb" {
  family                = "mongodb-task"
  network_mode          = "bridge"
  requires_compatibilities = ["EC2"]
  execution_role_arn    = var.task_execution_role_arn
  task_role_arn        = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "mongodb"
      image     = "mongo:4.4"
      essential = true
      memory    = 256
      
      portMappings = [
        {
          containerPort = 27017
          hostPort      = 27017
          protocol      = "tcp"
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.mongodb.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = var.tags
}

resource "aws_ecs_task_definition" "gateway" {
  family                = "gateway-task"
  network_mode          = "bridge"
  requires_compatibilities = ["EC2"]
  execution_role_arn    = var.task_execution_role_arn
  task_role_arn        = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "gateway"
      image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/microservice-gateway:latest"
      essential = true
      memory    = 256
      
      portMappings = [
        {
          containerPort = 80
          hostPort      = 0
          protocol      = "tcp"
        }
      ]
      
      environment = [
        {
          name  = "SERVICE_URL"
          value = "http://localhost:8080"
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.gateway.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = var.tags
}

resource "aws_ecs_task_definition" "worker" {
  family                = "worker-task"
  network_mode          = "bridge"
  requires_compatibilities = ["EC2"]
  execution_role_arn    = var.task_execution_role_arn
  task_role_arn        = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "worker"
      image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/microservice-worker:latest"
      essential = true
      memory    = 256
      
      portMappings = [
        {
          containerPort = 80
          hostPort      = 0
          protocol      = "tcp"
        }
      ]
      
      environment = [
        {
          name  = "DBHOST"
          value = "mongodb://localhost:27017"
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.worker.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = var.tags
}

resource "aws_ecs_service" "mongodb" {
  name            = "mongodb-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.mongodb.arn
  desired_count   = 1
  launch_type     = "EC2"

  depends_on = [aws_autoscaling_group.ecs_asg]

  tags = var.tags
}

resource "aws_ecs_service" "gateway" {
  name            = "gateway-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.gateway.arn
  desired_count   = 1
  launch_type     = "EC2"

  load_balancer {
    target_group_arn = var.alb_target_group_arns.gateway
    container_name   = "gateway"
    container_port   = 80
  }

  depends_on = [var.alb_target_group_arns, aws_autoscaling_group.ecs_asg]

  tags = var.tags
}

resource "aws_ecs_service" "worker" {
  name            = "worker-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = 1
  launch_type     = "EC2"

  load_balancer {
    target_group_arn = var.alb_target_group_arns.worker
    container_name   = "worker"
    container_port   = 80
  }

  depends_on = [var.alb_target_group_arns, aws_autoscaling_group.ecs_asg, aws_ecs_service.mongodb]

  tags = var.tags
}
