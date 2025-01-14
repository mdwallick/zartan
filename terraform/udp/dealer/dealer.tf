variable "org_name" {}
variable "api_token" {}
variable "base_url" {}
variable "demo_app_name" { default = "dealer" }
variable "udp_subdomain" { default = "local" }

locals {
  app_domain       = "${var.udp_subdomain}.${var.demo_app_name}.unidemo.info"
  nodash_subdomain = replace(var.udp_subdomain, "-", "_")
}

provider "okta" {
  org_name  = var.org_name
  api_token = var.api_token
  base_url  = var.base_url
  version   = "~> 3.0"
}
data "okta_group" "all" {
  name = "Everyone"
}
resource "okta_app_oauth" "dealer" {
  label       = "${var.udp_subdomain} ${var.demo_app_name} Demo (Generated by UDP)"
  type        = "web"
  grant_types = ["authorization_code"]
  redirect_uris = [
    "https://${local.app_domain}/authorization-code/callback",
    "http://localhost:8666/authorization-code/callback"
  ]
  post_logout_redirect_uris = [
    "https://${local.app_domain}/index",
    "http://localhost:8666/index"
  ]
  response_types = ["code"]
  issuer_mode    = "ORG_URL"
  consent_method = "TRUSTED"
  groups         = ["${data.okta_group.all.id}"]
}
resource "okta_trusted_origin" "dealer_https" {
  name   = "${var.udp_subdomain} ${var.demo_app_name} HTTPS"
  origin = "https://${local.app_domain}"
  scopes = ["REDIRECT", "CORS"]
}
resource "okta_auth_server" "dealer" {
  name        = "${var.udp_subdomain} ${var.demo_app_name}"
  description = "Generated by UDP"
  audiences   = ["api://${local.app_domain}"]
}
resource "okta_auth_server_policy" "dealer" {
  auth_server_id   = okta_auth_server.dealer.id
  status           = "ACTIVE"
  name             = "standard"
  description      = "Generated by UDP"
  priority         = 1
  client_whitelist = ["${okta_app_oauth.dealer.id}"]
}
resource "okta_auth_server_policy_rule" "dealer" {
  auth_server_id       = okta_auth_server.dealer.id
  policy_id            = okta_auth_server_policy.dealer.id
  status               = "ACTIVE"
  name                 = "one_hour"
  priority             = 1
  group_whitelist      = ["${data.okta_group.all.id}"]
  grant_type_whitelist = ["authorization_code", "implicit"]
  scope_whitelist      = ["*"]
}
resource "okta_auth_server_claim" "dealer" {
  auth_server_id          = okta_auth_server.dealer.id
  name                    = "groups"
  value_type              = "GROUPS"
  always_include_in_token = true
  group_filter_type       = "REGEX"
  value                   = ".*"
  claim_type              = "IDENTITY"
}
resource "okta_user_schema" "customfield1" {
  index       = "${local.nodash_subdomain}_${var.demo_app_name}_access_requests"
  title       = "${var.udp_subdomain}_${var.demo_app_name}_access_requests"
  type        = "array"
  array_type  = "string"
  description = "${var.udp_subdomain}_${var.demo_app_name}_access_requests contains workflow request"
  master      = "OKTA"
  scope       = "SELF"
  permissions = "READ_WRITE"
}

resource "okta_group" "dealer_admin" {
  name        = "${local.nodash_subdomain}_${var.demo_app_name}_ADMIN"
  description = "Dealer Portal Administrator"
}
resource "okta_group_rule" "dealer_group_rule" {
  name              = "${var.udp_subdomain} ${var.demo_app_name} Admin Rule"
  status            = "ACTIVE"
  group_assignments = ["${okta_group.dealer_admin.id}"]
  expression_type   = "urn:okta:expression:1.0"
  expression_value  = "String.stringContains(user.email,\"okta.com\")"
}
resource "okta_group" "dealer_user" {
  name        = "${local.nodash_subdomain}_${var.demo_app_name}_USER"
  description = "Dealer Regular User"
}
resource "okta_group" "dealer_loc1" {
  name        = "${local.nodash_subdomain}_${var.demo_app_name}_LOC_Austin"
  description = "Austin, Texas Branch"
}
resource "okta_group" "dealer_loc2" {
  name        = "${local.nodash_subdomain}_${var.demo_app_name}_LOC_Chicago"
  description = "Chicago, Illinois Branch"
}
resource "okta_group" "dealer_loc3" {
  name        = "${local.nodash_subdomain}_${var.demo_app_name}_LOC_SF"
  description = "San Fransisco, California Branch"
}
resource "okta_group" "dealer_loc4" {
  name        = "${local.nodash_subdomain}_${var.demo_app_name}_LOC_WashingtonDC"
  description = "Washingthon DC Branch"
}
output "client_id" {
  value = "${okta_app_oauth.dealer.client_id}"
}
output "client_secret" {
  value = "${okta_app_oauth.dealer.client_secret}"
}
output "domain" {
  value = "${var.org_name}.${var.base_url}"
}
output "auth_server_id" {
  value = "${okta_auth_server.dealer.id}"
}
output "issuer" {
  value = "${okta_auth_server.dealer.issuer}"
}
output "okta_app_oauth_id" {
  value = "${okta_app_oauth.dealer.id}"
}
