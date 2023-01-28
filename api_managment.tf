# Mapping of input variables to local variables
locals {
  resource_name   = "${var.resources_base_name}-${random_string.rnd.result}"
  location        = var.location
  publisher_name  = var.publisher_name
  publisher_email = var.publisher_email
  sku_name        = var.sku_name
  api_keys        = var.api_keys

  resource_group_name                 = "${var.resource_group_name}-rg"
  storage_account_name                = "${substr(replace(var.resources_base_name, "-", ""), 0, 14)}${random_string.rnd.result}sa"
  application_insights                = "${var.resources_base_name}${random_string.rnd.result}-appi"
  api_management_name                 = "${var.resources_base_name}${random_string.rnd.result}-apim"
  api_management_logger               = "${var.resources_base_name}${random_string.rnd.result}-log"
  cdn_profile_name                    = "${var.resources_base_name}${random_string.rnd.result}-cdnprofile"
  cdn_endpoint_name                   = "${var.resources_base_name}${random_string.rnd.result}-endpoint"
  cdn_endpoint_origin_name            = "${var.resources_base_name}${random_string.rnd.result}-origin"
  cdn_endpoint_custom_domain_name     = "${var.resources_base_name}-domain"
  cdn_endpoint_custom_sub_domain_name = "${var.resources_base_name}-sub-domain"

  dns_resource_group_name = var.sub_domain_dns.resource_group_name
  dns_zone_name           = var.sub_domain_dns.zone_name
  dns_root_domain         = var.sub_domain_dns.root_domain
  dns_sub_domain_name     = var.sub_domain_dns.sub_domain_name

  url       = "${var.sub_domain_dns.sub_domain_name}.${var.sub_domain_dns.root_domain}"
  https_url = "https://${var.sub_domain_dns.sub_domain_name}.${var.sub_domain_dns.root_domain}"
}

# Generate random UUID as identifier between API Management and CDN
resource "random_uuid" "uuid" {
}

# Generate random string as suffix for resources
resource "random_string" "rnd" {
  length  = 8
  special = false
  upper   = false
}

# Create resource group
resource "azurerm_resource_group" "rg" {
  name     = local.resource_group_name
  location = local.location
}

# Application insights for API Management
resource "azurerm_application_insights" "api-insights" {
  name                = local.application_insights
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
}

# Logger for API Management
resource "azurerm_api_management_logger" "logger" {
  name                = local.api_management_logger
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  application_insights {
    instrumentation_key = azurerm_application_insights.api-insights.instrumentation_key
  }
}

# Diagnostic for API Management
resource "azurerm_api_management_diagnostic" "diag" {
  identifier               = "applicationinsights"
  resource_group_name      = azurerm_resource_group.rg.name
  api_management_name      = azurerm_api_management.apim.name
  api_management_logger_id = azurerm_api_management_logger.logger.id
}

# Creates API Management
# Adds policy to check for header x-apim-origin-key, so that only CDN can access the API Management
resource "azurerm_api_management" "apim" {
  name                = local.api_management_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  publisher_name      = local.publisher_name
  publisher_email     = local.publisher_email
  sku_name            = var.sku_name

  policy {
    xml_content = <<XML
    <policies>
        <inbound>
            <check-header name="x-apim-origin-key" failed-check-httpcode="404" failed-check-error-message="" ignore-case="true">
                <value>${random_uuid.uuid.id}</value>
            </check-header>
        </inbound>
        <backend>
            <forward-request />
        </backend>
        <outbound />
        <on-error />
    </policies>
    XML
  }
}

# Subscriptions over "API Keys" for API Management
resource "azurerm_api_management_subscription" "subscriptions" {
  for_each = {
    for index, api_key in local.api_keys :
    api_key.name => api_key
  }

  resource_group_name = azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  display_name        = each.value.name
  state               = "active"
  primary_key         = each.value.key
}

# CDN Profile
resource "azurerm_cdn_profile" "apim-cdnprofile" {
  name                = local.cdn_profile_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard_Microsoft"
}

# CDN Endpoint
resource "azurerm_cdn_endpoint" "apim-endpoint" {
  name                = local.cdn_endpoint_name
  profile_name        = azurerm_cdn_profile.apim-cdnprofile.name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  origin_host_header  = trimprefix(azurerm_api_management.apim.gateway_url, "https://")

  origin {
    name      = local.cdn_endpoint_origin_name
    host_name = trimprefix(azurerm_api_management.apim.gateway_url, "https://")
  }

  global_delivery_rule {
    modify_request_header_action {
      action = "Append"
      name   = "x-apim-origin-key"
      value  = random_uuid.uuid.id
    }

    modify_response_header_action {
      action = "Delete"
      name   = "X-AspNet-Version"
    }

    modify_response_header_action {
      action = "Delete"
      name   = "X-Powered-By"
    }

    modify_response_header_action {
      action = "Delete"
      name   = "X-Azure-Ref-OriginShield"
    }
  }

  delivery_rule {
    name  = "EnforceCustomDomainRedirect"
    order = "1"

    request_uri_condition {
      operator         = "BeginsWith"
      negate_condition = true
      match_values     = [local.https_url]
    }

    url_redirect_action {
      redirect_type = "PermanentRedirect"
      protocol      = "Https"
      hostname      = local.url
    }
  }
}

# Create CNAME record (sub-domain) for CDN endpoint
resource "azurerm_dns_cname_record" "cname_record" {
  name                = local.dns_sub_domain_name
  zone_name           = local.dns_zone_name
  resource_group_name = local.dns_resource_group_name
  ttl                 = 300
  target_resource_id  = azurerm_cdn_endpoint.apim-endpoint.id
}

# Connects the CDN endpoint to the CNAME record
resource "azurerm_cdn_endpoint_custom_domain" "cdn_custom_domain" {
  name            = local.cdn_endpoint_custom_domain_name
  cdn_endpoint_id = azurerm_cdn_endpoint.apim-endpoint.id
  host_name       = local.url

  cdn_managed_https {
    certificate_type = "Dedicated"
    protocol_type    = "ServerNameIndication"
    tls_version      = "TLS12"
  }

  depends_on = [
    azurerm_dns_cname_record.cname_record
  ]
}

# Removes the CNAME record when the CDN endpoint is destroyed
resource "null_resource" "destroy_cname_record" {
  triggers = {
    uuid                = azurerm_cdn_endpoint_custom_domain.cdn_custom_domain.id
    resource_group_name = local.dns_resource_group_name
    zone_name           = local.dns_zone_name
    sub_domain_name     = local.dns_sub_domain_name
  }

  provisioner "local-exec" {
    when    = destroy
    command = "az network dns record-set cname delete -g ${self.triggers.resource_group_name} -z ${self.triggers.zone_name} -n ${self.triggers.sub_domain_name} -y"
  }
}
