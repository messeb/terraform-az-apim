terraform {
  cloud {
    organization = "messeb"

    workspaces {
      name = "terraform-az-apim"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Deletes external resources if resource groups are deleted
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}

module "apim" {
  source = "github.com/messeb/terraform-az-apim.git"

  resource_group_name = "az-api-management"
  resources_base_name = "az-api-management"
  location            = "westeurope"
  publisher_email     = "noreplay@messeb.net"
  publisher_name      = "messeb"
  sku_name            = "Consumption_0"

  api_keys = [
    {
      name = "ApiKey01"
      key  = "f1a9b055-638a-4b4b-8b77-58ae5a602aab"
    }
  ]

  sub_domain_dns = {
    resource_group_name = "messeb"
    zone_name           = "messeb.net"
    root_domain         = "messeb.net"
    sub_domain_name     = "az-api-management"
  }
}
