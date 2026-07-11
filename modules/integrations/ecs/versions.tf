terraform {
  # >= 1.9.0 to stay consistent with the Phase 1 modules (which use
  # cross-variable validation).
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
