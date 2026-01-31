# Staging environment - cochlearis-infra

module "vpc" {
  source = "../../../modules/aws/vpc"

  project     = var.project
  environment = var.environment

  vpc_cidr             = "10.1.0.0/16"
  availability_zones   = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
  private_subnet_cidrs = ["10.1.11.0/24", "10.1.12.0/24", "10.1.13.0/24"]
}

module "ecs" {
  source = "../../../modules/aws/ecs-cluster"

  project     = var.project
  environment = var.environment

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
}
