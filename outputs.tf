output "srv1" {
	value = "${digitalocean_droplet.srv.0.ipv4_address}"
}

output "srv2" {
	value = "${digitalocean_droplet.srv.1.ipv4_address}"
}
