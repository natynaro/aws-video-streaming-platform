terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    local = {
      source = "hashicorp/local"
    }
  }

  # Shared team state on GitLab (gin852423/GIN207).
  # Init: ./init-backend.sh (requires glab + OpenTofu).
  backend "http" {
    address        = "https://gitlab.com/api/v4/projects/82756259/terraform/state/default"
    lock_address   = "https://gitlab.com/api/v4/projects/82756259/terraform/state/default/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/82756259/terraform/state/default/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = "default"
}
