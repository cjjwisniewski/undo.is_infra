resource "azurerm_resource_group" "rg" {
  name     = "${local.project_prefix}site"
  location = local.region
  tags     = local.tags
}
