terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "cochlearis-infra-tf-state"
    key            = "aws/staging/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "cochlearis-infra-tf-lock"
    encrypt        = true
  }
}
