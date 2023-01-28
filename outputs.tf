output "api_management_url" {
  description = "URL of the API Management"
  value       = local.https_url
}

output "api_management_name" {
  description = "Name of the API Management"
  value       = azurerm_api_management.apim.name
}

output "api_management_resource_group_name" {
  description = "Resource group name of the API Management"
  value       = azurerm_resource_group.rg.name
}

output "api_management_location" {
  description = "Location of the API Management"
  value       = azurerm_resource_group.rg.location
}
