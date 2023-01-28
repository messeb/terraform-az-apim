variable "resource_group_name" {
  description = "Name of the resource group"
}

variable "resources_base_name" {
  description = "Base name of the resources"
}

variable "location" {
  description = "Location of the resources"
}

variable "publisher_name" {
  description = "Name of the publisher"
}

variable "publisher_email" {
  description = "Email of the publisher"
}

variable "sku_name" {
  description = "SKU name of the API Management"
  default     = "Consumption_0"
}

variable "sub_domain_dns" {
  type = object({
    resource_group_name = string
    zone_name           = string
    root_domain         = string
    sub_domain_name     = string
  })

  description = "Configuration for subdomain of the CDN endpoint"
}

variable "api_keys" {
  type = list(object({
    name = string
    key  = string
  }))

  description = "List of API keys"
  default     = []
}
