terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source = "./modules/vpc"
  
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  
  tags = var.tags
}

module "iam" {
  source = "./modules/iam"
  tags   = var.tags
}

module "ecr" {
  source = "./modules/ecr"
  
  repository_names = var.ecr_repositories
  tags            = var.tags
}

module "alb" {
  source = "./modules/alb"
  
  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = module.vpc.public_subnet_ids
  alb_name           = var.alb_name
  
  tags = var.tags
}

module "ecs" {
  source = "./modules/ecs"
  
  cluster_name           = var.ecs_cluster_name
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  alb_target_group_arns = module.alb.target_group_arns
  alb_security_group_id = module.alb.alb_security_group_id
  task_execution_role_arn = module.iam.ecs_task_execution_role_arn
  task_role_arn         = module.iam.ecs_task_role_arn
  
  tags = var.tags
}
