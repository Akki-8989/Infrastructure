terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "app_name" {
  type        = string
  description = "Application name"
}

variable "location" {
  type    = string
  default = "Central India"
}

variable "sql_admin_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "project_type" {
  type    = string
  default = "backend"
}

variable "backend_api_url" {
  type    = string
  default = ""
}

variable "backend_urls" {
  type    = string
  default = ""
}

locals {
  resource_prefix   = replace(replace(lower(var.app_name), "_", "-"), ".", "-")
  create_sql_server = var.sql_admin_password != "" && var.project_type == "backend"
  is_frontend       = var.project_type == "frontend"
  is_backend        = var.project_type == "backend"
  create_gateway    = var.backend_urls != "" && local.is_frontend
}

resource "azurerm_resource_group" "main" {
  name     = "${local.resource_prefix}-rg"
  location = var.location
}

resource "azurerm_service_plan" "main" {
  count               = local.is_backend ? 1 : 0
  name                = "${local.resource_prefix}-plan"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Windows"
  sku_name            = "F1"
}

resource "azurerm_windows_web_app" "main" {
  count               = local.is_backend ? 1 : 0
  name                = "${local.resource_prefix}-webapp"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main[0].id

  site_config {
    always_on = false
    application_stack {
      dotnet_version = "v8.0"
    }
  }

  app_settings = {
    "ASPNETCORE_ENVIRONMENT" = "Production"
  }

  dynamic "connection_string" {
    for_each = local.create_sql_server ? [1] : []
    content {
      name  = "DefaultConnection"
      type  = "SQLAzure"
      value = "Server=tcp:${azurerm_mssql_server.main[0].fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.main[0].name};User ID=sqladmin;Password=${var.sql_admin_password};Encrypt=true;TrustServerCertificate=false;"
    }
  }
}

resource "azurerm_mssql_server" "main" {
  count                        = local.create_sql_server ? 1 : 0
  name                         = "${local.resource_prefix}-sqlserver"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = var.sql_admin_password
}

resource "azurerm_mssql_database" "main" {
  count     = local.create_sql_server ? 1 : 0
  name      = "${local.resource_prefix}-db"
  server_id = azurerm_mssql_server.main[0].id
  sku_name  = "Basic"
}

resource "azurerm_static_web_app" "main" {
  count               = local.is_frontend ? 1 : 0
  name                = "${local.resource_prefix}-static"
  resource_group_name = azurerm_resource_group.main.name
  location            = "eastasia"
  sku_tier            = "Free"
  sku_size            = "Free"
}

resource "azurerm_service_plan" "gateway" {
  count               = local.create_gateway ? 1 : 0
  name                = "${local.resource_prefix}-gateway-plan"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Windows"
  sku_name            = "F1"
}

resource "azurerm_windows_web_app" "gateway" {
  count               = local.create_gateway ? 1 : 0
  name                = "${local.resource_prefix}-gateway-webapp"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.gateway[0].id

  site_config {
    always_on = false
    application_stack {
      dotnet_version = "v8.0"
    }
  }

  app_settings = {
    "ASPNETCORE_ENVIRONMENT" = "Production"
    "BACKEND_URLS"           = var.backend_urls
  }
}

output "resource_group" {
  value = azurerm_resource_group.main.name
}

output "webapp_name" {
  value = local.is_backend ? azurerm_windows_web_app.main[0].name : ""
}

output "static_webapp_name" {
  value = local.is_frontend ? azurerm_static_web_app.main[0].name : ""
}

output "gateway_webapp_name" {
  value = local.create_gateway ? azurerm_windows_web_app.gateway[0].name : ""
}
