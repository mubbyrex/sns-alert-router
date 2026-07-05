terraform {
  # >= 1.9.0: kept consistent with the receiver modules, which rely on
  # cross-variable validation (added in Terraform 1.9.0).
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
