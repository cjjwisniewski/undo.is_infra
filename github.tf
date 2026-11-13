data "azurerm_subscription" "primary" {}
data "azuread_client_config" "current" {}

resource "azuread_application" "github_deploy" {
  display_name = "${local.project_prefix}-github-deploy"
  owners       = [data.azuread_client_config.current.object_id]

  lifecycle {
    ignore_changes = [owners]
  }
}

resource "azuread_service_principal" "github_deploy" {
  client_id                    = azuread_application.github_deploy.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]

  lifecycle {
    ignore_changes = [owners]
  }
}

resource "azuread_application_federated_identity_credential" "github_deploy" {
  application_id = azuread_application.github_deploy.id
  display_name   = "github-actions-deploy"
  description    = "Deploy from GitHub Actions"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${local.github_repo}:ref:refs/heads/main" # Scoped to the `main` branch
}

# Grant the Service Principal permission to upload blobs to the Storage Account
resource "azurerm_role_assignment" "github_deploy_storage" {
  scope                = azurerm_storage_account.static_site.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.github_deploy.object_id
}
