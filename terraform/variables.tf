variable "cloudflare_api_token" {
  type = string
}

variable "cloudflare_account_id" {
  type = string
}

variable "cloudflare_zone_id" {
  type = string
}

variable "minecraft_subdomain" {
  default = "minecraft"
  type    = string
}

variable "domain" {
  type = string
}

variable "minecraft_service_url" {
  type = string
}

variable "kubeconfig_path" {
  type = string
}
