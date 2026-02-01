terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    zitadel = {
      source  = "zitadel/zitadel"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    bucket         = "cochlearis-infra-tf-state"
    key            = "aws/dev/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "cochlearis-infra-tf-lock"
    encrypt        = true
  }
}
