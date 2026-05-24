variable "cloudflare_api_token" {
  type = string
  sensitive = true
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
  default = "cglavin50.com"
}

variable "private_ip" {
  type = string
  description = "Content val to assign root wildcard + a records. used for LAN access"
}

variable "minecraft_service_url" {
  type = string
  description = "Local URL of minecraft server to point cloudflare tunnel at"
}

variable "kubeconfig_path" {
  type = string
  default = "../k3s.yaml"
}
