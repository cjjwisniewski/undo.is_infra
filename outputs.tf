output "resource_group_name" {
  description = "Name of the resource group."
  value       = azurerm_resource_group.rg.name
}

output "storage_account_name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.static_site.name
}

output "storage_primary_web_endpoint" {
  description = "Primary web endpoint of the storage account."
  value       = azurerm_storage_account.static_site.primary_web_endpoint
}

output "cloudflare_cname_target" {
  description = "Target for the CNAME record in Cloudflare."
  value       = azurerm_storage_account.static_site.primary_web_host
}

output "azure_client_id" {
  description = "Client ID of the Azure AD Application for GitHub Actions."
  value       = azuread_application.github_deploy.client_id
}

output "azure_tenant_id" {
  description = "Tenant ID of the Azure AD."
  value       = data.azuread_client_config.current.tenant_id
}

output "azure_subscription_id" {
  description = "Subscription ID of the Azure Subscription."
  value       = data.azurerm_subscription.primary.subscription_id
}
