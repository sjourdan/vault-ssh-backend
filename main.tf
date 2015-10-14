provider "digitalocean" {
  token = "${var.do_token}"
}

resource "digitalocean_ssh_key" "default" {
  name = "Vault SSH Demo DO SSH Key"
  public_key = "${file("${var.ssh_key_file}.pub")}"
}

resource "digitalocean_droplet" "srv" {
  image = "ubuntu-15-04-x64"
  count = 2
  name = "srv-${count.index+1}"
  region = "${var.region}"
  size = "512mb"
  ssh_keys = ["${digitalocean_ssh_key.default.id}"]
  private_networking = true
}
