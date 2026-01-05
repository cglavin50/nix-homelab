output "minecraft_domain" {
  description = "Public Minecraft server domain"
  value       = "${var.minecraft_subdomain}.${var.domain}"
}
