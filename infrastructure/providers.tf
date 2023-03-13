terraform {
  backend "s3" {
    region  = "ca-central-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.36"
    }
  }
}

provider "aws" {
  region  = "ca-central-1"

  default_tags {
    tags = {
      app = "lambda-xray"
    }
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
