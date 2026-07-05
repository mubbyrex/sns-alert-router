terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Consumer-level tagging is the CONSUMER's responsibility, applied here via the
# provider's default_tags — NOT enforced by modules/core. Every resource this
# root module (and the modules it calls) creates inherits these tags
# automatically, which is how the CLAUDE.md Project / Environment / ManagedBy
# tagging convention is satisfied without baking tag variables into the module.
#
# The module still sets its own module-specific tag (SeverityTier) on each
# topic; that merges with the default_tags below rather than replacing them.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "sns-alert-router"
      Environment = "example"
      ManagedBy   = "terraform"
    }
  }
}

variable "aws_region" {
  description = "AWS region to deploy the standalone example into."
  type        = string
  default     = "us-east-1"
}
