terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.8"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }
  required_version = ">1.14"
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

# DNS
resource "cloudflare_dns_record" "root" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  ttl     = 1
  content = "192.168.1.50" # LAN access
  type    = "A"
  proxied = false
  comment = "Home server LAN for non-tunneled services"
}

resource "cloudflare_dns_record" "wildcard" {
  zone_id = var.cloudflare_zone_id
  name    = "*"
  ttl     = 1
  content = "192.168.1.50" # LAN access
  type    = "A"
  proxied = false
  comment = "Home server LAN wildcard dns"
}

resource "cloudflare_dns_record" "tunnel_txt" {
  zone_id = var.cloudflare_zone_id
  name    = var.minecraft_subdomain
  type    = "TXT"
  ttl     = 60
  content = "cloudflared-route=${var.minecraft_subdomain}.${var.domain}"
  proxied = false
  comment = "Tunnel access to Minecraft server"
}

resource "cloudflare_dns_record" "tunnel" {
  zone_id = var.cloudflare_zone_id
  name    = var.minecraft_subdomain
  type    = "CNAME"
  ttl     = 1
  content = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
  proxied = true
  comment = "Tunnel access to Minecraft server"
}

# Tunnel
resource "cloudflare_zero_trust_tunnel_cloudflared" "this" {
  account_id = var.cloudflare_account_id
  name       = "Minecraft Server Tunnel"
  config_src = "local" # manage via cloudflare console
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id
  config = {
    ingress = [
      {
        hostname = "${var.minecraft_subdomain}.${var.domain}"
        service  = "tcp://${var.minecraft_service_url}"
      },
      {
        service = "http_status:404"
      }
    ]
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "this" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id
}

resource "kubernetes_secret_v1" "cloudflare_credentials" {
  metadata {
    name      = "cloudflared-token"
    namespace = "cloudflared"
  }

  data = {
    token = data.cloudflare_zero_trust_tunnel_cloudflared_token.this.token
  }

  type = "Opaque"
}
