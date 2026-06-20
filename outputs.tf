output "vm_addresses" {
  description = "Internal IPs of the managed VMs"
  value       = { for k, v in var.vms : k => v.ip }
}

output "netservices_gateway" {
  description = "Internal gateway / DNS (the netservices LXC)"
  value       = var.internal_gateway
}

output "coolify_url" {
  description = "Coolify dashboard (reach over Tailscale once the subnet route is approved)"
  value       = "http://${var.vms["prod"].ip}:8000"
}
