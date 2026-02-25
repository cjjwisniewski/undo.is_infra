locals {
  region         = "eastus2"
  domain_name    = "undo.is"
  project_prefix = "undois"
  github_repo    = "cjjwisniewski/undo.is"
  tags = {
    Project     = "undois"
    Environment = "Production"
    ManagedBy   = "Terraform"
  }
}
