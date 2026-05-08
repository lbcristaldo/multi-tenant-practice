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
  }
}

provider "aws" {
  # LocalStack (test local) o AWS real 
  endpoints {
    iam  = var.use_localstack ? "http://localhost:4566" : null
    sts  = var.use_localstack ? "http://localhost:4566" : null
    s3   = var.use_localstack ? "http://localhost:4566" : null
  }
  skip_credentials_validation = var.use_localstack
  s3_use_path_style           = var.use_localstack
  region                      = var.aws_region
}

