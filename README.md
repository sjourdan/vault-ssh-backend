# Vault SSH Backend Infrastructure

This idea here is simple:

* 1 server will run [Vault](https://vaultproject.io/) with a [Consul](https://consul.io/) backend.
* Other servers will authenticate against it with One-Time Passwords (OTP)

The Vault/Consul combo will be entirely run through docker containers: [docker-vault](https://github.com/sjourdan/docker-vault) and [Progrium's Consul](https://hub.docker.com/r/progrium/consul/).

The authentication will use the [Vault SSH Helper](https://github.com/hashicorp/vault-ssh-helper) on every node.

This demo runs on Digital Ocean with an Ubuntu image, but can be adapted to anything.

## Deploy the base infrastructure

Fill in the blanks in the configuration file, don't forget SSH keys under `keys`.

    $ cp terraform.tfvars.example terraform.tfvars
    $ terraform apply

Note the outputted IPs, we'll need them later.

## Login

Choose the first server:

    $ ssh -i keys/vault-ssh-demo root@a.b.c.d

The first one will be the Vault + Consul server, the other one will just be a normal OTP authentication client.

## Install Docker

We'll need Docker, so let's install it quickly:

    # wget -qO- https://get.docker.com/ | sh

## Run Consul

Now run a Consul container:

    # docker run -d -p 8400:8400 -p 8500:8500 -p 8600:53/udp --hostname consul --name consul progrium/consul -server -bootstrap -ui-dir /ui    
Verify it's working great and no error on the logs:

    # docker logs -f consul

## Run Vault

To begin with, we need to create a Vault configuration directory:

    # mkdir /etc/vault

Add a simple configuration file for consul (found here under `config/vault.hcl.sample`):

    # root@srv-1:~# cat /etc/vault/vault.hcl
    backend "consul" {
    address = "consul:8500"
    path = "demo_vault"
    advertise_addr = "http://127.0.0.1"
    }

    listener "tcp" {
    address = "0.0.0.0:8200"
    tls_disable = 1
    }

    disable_mlock = true

The name `consul` will work because we'll link to this name when we'll run the Vault container. If you choose to have a dedicated host for it: use its name or IP.

Start Vault with Consul backend support:

    # docker run -d -p 8200:8200 --name vault --link consul:consul --volume /etc/vault:/etc/vault sjourdan/vault -config=/etc/vault/vault.hcl

Check everything's OK by looking at the logs:

    # docker logs -f vault

## Configure Vault

Setup quickly the container as a configured client for the local vault server:

We'll need a token later on, let's prepare for this:

    # touch ~/.vault-token

Use an alias for the whole command, it will be much easier this way:

    # alias vault="docker run --rm --link vault:vault -e VAULT_ADDR=http://vault:8200 -v $HOME/.vault-token:$HOME/.vault-token sjourdan/vault"

Does it work?

    # vault version
    Vault v0.3.1

Check the status:

    # vault status

Should say that `it is not yet initialized`. Great!

## Initialize & Unseal Vault

Let's initialize Vault from the main server:

    $ vault init
    Key 1: 9a173c5c001b892f29ceaf47931280bce943af30e57c03b64c685b903681df1a01
    Key 2: cc7764c827f62414da313a37aaeedb204d7e6edfe4e460c1e6acf91dc5a5facc02
    Key 3: 524b6d2dbb023d0f03ae43dff39b2fec270171e6d26c67dc9a023540a36f3c3603
    Key 4: 1e0380eda758cd2c9e9e6dd36ff95ab16c7eba18cab87f243fa6d2c51e130f9904
    Key 5: 803f89083bacd4374701143b368cae7d0601a521fc30783943081e9878d9c96305
    Initial Root Token: c58e9edb-6136-cd94-7809-88fbac1aa8b8

That's 5 keys and a root token.

Unseal the vault with 3 keys of your choice:

    # vault unseal <key_1>
    # vault unseal <key_2>
    # vault unseal <key_3>

It's now unsealed!

## Authenticate against the Vault

Use the above "Initial Root Token":

    # vault auth <initial_root_token>

## Mount SSH Vault Backend

The backend needs to be explicitely mounted:

    # vault mount ssh

## Create a local "admin" user

On both servers, let's use an `admin` user that we'll use with OTPs:

    # adduser admin

## Configure SSH Vault Backend

### Create a role

Our LAN is `10.135.0.0/16`, let's create a role for it (and the `admin` user we just created)

    # vault write ssh/roles/otp_key_role key_type=otp default_user=admin cidr_list=10.135.0.0/16
    Success! Data written to: ssh/roles/otp_key_role

## Build & Configure PAM with Vault SSH Helper

Those instructions are to be repeated on every server to be managed by Vault OTP.

To save time, we've pre-built the Vault's SSH Helper, but you can find more information on the BUILD.md page.

* Download /install the helper under `/usr/local/bin`:

`wget http://greenalto.s3.amazonaws.com/vault/vault-ssh-helper.tar.gz`

* Create a configuration file with the local Vault server local IP (here 10.135.136.198):

```
# mkdir /etc/vault-ssh-helper
# cat /etc/vault-ssh-helper/config.hcl
vault_addr="http://10.135.136.198:8200"
ssh_mount_point="ssh"
```

* Edit PAM sshd config `/etc/pam.d/sshd`

* Comment out: `#@include common-auth`
* replace by:

```
auth requisite pam_exec.so quiet expose_authtok log=/tmp/vaultssh.log /usr/local/bin/vault-ssh-helper -config-file=/etc/vault-ssh-helper/config.hcl
auth optional pam_unix.so no_set_pass use_first_pass nodelay
```

* Edit sshd configuration in `/etc/ssh/sshd_config`:

```
ChallengeResponseAuthentication yes
UsePAM yes
PasswordAuthentication no
```

* Restart OpenSSH

`# systemctl restart ssh`

* Verify the connectivity is okay:

```
# vault-ssh-helper -verify -config-file=/etc/vault-ssh-helper/config.hcl
2015/10/14 10:26:22 [INFO] Using SSH Mount point: ssh
2015/10/14 10:26:22 [INFO] Agent verification successful!
```

### Create a credential

On the Vault server, create an OTP for the second remote server `10.135.137.205`:

    # vault write ssh/creds/otp_key_role ip=10.135.137.205
    Key             Value
    lease_id        ssh/creds/otp_key_role/7973493e-072c-4531-29ff-e8403eb0b4df
    lease_duration  2592000
    lease_renewable false
    ip              10.135.137.205
    key             5287717e-9154-c44d-db10-e49ba8da2815
    key_type        otp
    port            22
    username        admin

Then try to login:

    root@srv-1:~# ssh admin@10.135.137.205
    Password:
    Welcome to Ubuntu 15.04 (GNU/Linux 3.19.0-22-generic x86_64)

If you have the `vault` command configured, you can use the following in a single command:

    # vault ssh -role otp_key_role admin@10.135.137.205
    OTP for the session is `5287717e-9154-c44d-db10-e49ba8da2815`
    [Note: Install `sshpass` to automate typing in OTP]
    Password: <Enter OTP>

You're done! The servers are using OTPs.

## Destroy

As usual when you're done with it:

    $ terraform destroy

## Sources

* [Announcing Vault 0.3](https://www.hashicorp.com/blog/vault-0.3.html)
* [Vault SSH Secret Backend](https://vaultproject.io/docs/secrets/ssh/index.html)
* [Vault SSH Helper](https://github.com/hashicorp/vault-ssh-helper)
