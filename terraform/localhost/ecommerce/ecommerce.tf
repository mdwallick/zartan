variable "org_name" {}
variable "api_token" {}
variable "base_url" {}
variable "demo_app_name" { default = "ecommerce" }
variable "udp_subdomain" { default = "local" }

locals {
  app_domain       = var.udp_subdomain != "local" ? format("%s.%s.unidemo.info") : format("%s.%s", var.udp_subdomain, var.demo_app_name)
  nodash_subdomain = replace(var.udp_subdomain, "-", "_")
}

terraform {
  required_providers {
    okta = {
      source  = "okta/okta"
      version = "~> 3.17"
    }
  }
}

provider "okta" {
  org_name  = var.org_name
  api_token = var.api_token
  base_url  = var.base_url
}

data "okta_group" "all" {
  name = "Everyone"
}

resource "okta_group" "buyer_group" {
  name        = "${var.udp_subdomain}_${var.demo_app_name}_buyer"
  description = "${var.udp_subdomain} Buyer Group"
}

resource "okta_group" "employee_group" {
  name        = "${var.udp_subdomain}_${var.demo_app_name}_employee"
  description = "${var.udp_subdomain} Employee Group"
}

resource "okta_group_rule" "buyer_group_rule" {
  name              = "${var.udp_subdomain} ${var.demo_app_name} Buyer Rule"
  status            = "ACTIVE"
  group_assignments = ["${okta_group.buyer_group.id}"]
  expression_type   = "urn:okta:expression:1.0"
  expression_value  = "String.stringContains(user.email,\"okta.com\")"
  depends_on        = [okta_group.buyer_group]
}

resource "okta_group_rule" "employee_group_rule" {
  name              = "${var.udp_subdomain} ${var.demo_app_name} Employee Rule"
  status            = "ACTIVE"
  group_assignments = ["${okta_group.employee_group.id}"]
  expression_type   = "urn:okta:expression:1.0"
  expression_value  = "String.stringContains(user.email,\"okta.com\")"
  depends_on        = [okta_group.employee_group]
}

resource "okta_app_oauth" "ecommerce" {
  label       = format("%s DEMO (Generated by UDP)", local.app_domain)
  type        = "web"
  grant_types = ["authorization_code"]
  redirect_uris = [
    "https://${local.app_domain}/authorization-code/callback",
    "http://localhost:8666/authorization-code/callback"
  ]
  post_logout_redirect_uris = [
    "http://localhost:8666/index"
  ]
  response_types = ["code"]
  consent_method = "TRUSTED"
  issuer_mode    = "ORG_URL"
  lifecycle {
    ignore_changes = [groups]
  }
}

resource "okta_app_group_assignments" "ecommerce" {
  app_id = okta_app_oauth.ecommerce.id
  group {
    id       = okta_group.buyer_group.id
    priority = 1
  }
  group {
    id       = okta_group.employee_group.id
    priority = 2
  }
}

resource "okta_trusted_origin" "ecommerce" {
  name   = format("%s: 8666", local.app_domain)
  origin = "https://${local.app_domain}"
  scopes = ["REDIRECT", "CORS"]
}

resource "okta_auth_server" "ecommerce" {
  name        = local.app_domain
  description = format("%s (Generated by UDP)", local.app_domain)
  audiences   = ["api://${local.app_domain}"]
}

resource "okta_auth_server_policy" "ecommerce" {
  auth_server_id   = okta_auth_server.ecommerce.id
  status           = "ACTIVE"
  name             = "standard"
  description      = "Generated by UDP"
  priority         = 1
  client_whitelist = [okta_app_oauth.ecommerce.id]
}

resource "okta_auth_server_policy_rule" "ecommerce" {
  auth_server_id       = okta_auth_server.ecommerce.id
  policy_id            = okta_auth_server_policy.ecommerce.id
  status               = "ACTIVE"
  name                 = "one_hour"
  priority             = 1
  group_whitelist      = [data.okta_group.all.id]
  grant_type_whitelist = ["authorization_code", "implicit"]
  scope_whitelist      = ["*"]
}

resource "okta_auth_server_claim" "ecommerce" {
  auth_server_id    = okta_auth_server.ecommerce.id
  name              = "groups"
  status            = "ACTIVE"
  claim_type        = "IDENTITY"
  value_type        = "GROUPS"
  group_filter_type = "REGEX"
  value             = ".*"
}

resource "okta_user_schema_property" "customfield1" {
  index       = "${local.nodash_subdomain}_${var.demo_app_name}_last_verified_date"
  title       = "${var.udp_subdomain}_${var.demo_app_name}_last_verified_date"
  type        = "string"
  description = "Date Evident Last Verified"
  master      = "OKTA"
  scope       = "SELF"
  permissions = "READ_WRITE"
}

resource "okta_user_schema_property" "customfield2" {
  index       = "${local.nodash_subdomain}_${var.demo_app_name}_evident_id"
  title       = "${var.udp_subdomain}_${var.demo_app_name}_evident_id"
  type        = "string"
  description = "Evident ID"
  master      = "OKTA"
  scope       = "SELF"
  permissions = "READ_WRITE"
  depends_on  = [okta_user_schema_property.customfield1]
}

resource "okta_user_schema_property" "customfield3" {
  index       = "${local.nodash_subdomain}_${var.demo_app_name}_access_requests"
  title       = "${var.udp_subdomain}_${var.demo_app_name}_access_requests"
  type        = "array"
  array_type  = "string"
  description = "Contains Applications Requests"
  master      = "OKTA"
  scope       = "SELF"
  permissions = "READ_WRITE"
  depends_on  = [okta_user_schema_property.customfield2]
}

resource "okta_user_schema_property" "customfield4" {
  index       = "${local.nodash_subdomain}_${var.demo_app_name}_consent"
  title       = "${var.udp_subdomain}_${var.demo_app_name}_consent"
  type        = "string"
  description = "Date Consensted"
  master      = "OKTA"
  scope       = "SELF"
  permissions = "READ_WRITE"
  depends_on  = [okta_user_schema_property.customfield3]
}

# Create the .env file
resource "local_file" "dotenv" {
  content = templatefile("${path.module}/ecommerce.dotenv.tpl", {
    client_id         = okta_app_oauth.ecommerce.client_id,
    client_secret     = okta_app_oauth.ecommerce.client_secret,
    domain            = format("%s.%s", var.org_name, var.base_url),
    auth_server_id    = okta_auth_server.ecommerce.id,
    okta_app_oauth_id = okta_app_oauth.ecommerce.id
  })

  filename = format("%s/%s.env", "${path.module}", var.demo_app_name)
}

# Output to the terminal
output "client_id" {
  value = okta_app_oauth.ecommerce.client_id
}

output "client_secret" {
  value     = okta_app_oauth.ecommerce.client_secret
  sensitive = true
}

output "domain" {
  value = format("%s.%s", var.org_name, var.base_url)
}

output "auth_server_id" {
  value = okta_auth_server.ecommerce.id
}

output "issuer" {
  value = okta_auth_server.ecommerce.issuer
}

output "okta_app_oauth_id" {
  value = okta_app_oauth.ecommerce.id
}
