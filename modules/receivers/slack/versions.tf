terraform {
  # >= 1.9.0: severity_tiers validation references another variable
  # (topic_arns), which requires cross-variable validation support.
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
