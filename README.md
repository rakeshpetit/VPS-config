## Introduction

Configuration to manage my VPS server if things accidentally go wrong.

## Login to my VPS server

```shell
# First time
ssh -i  private_key_rsa_file root@OUR_IP_ADDRESS
# Subsequent connections
ssh root@OUR_IP_ADDRESS
```

## Enable Firewall

- Navigate to https://console.hetzner.cloud/ and open Firewalls.
- Add inbound rules such that only 3 ports are open on the machine.
- TCP port 22 for SSH
- TCP port 80 for HTTP
- TCP port 443 for HTTPS

## Copy files from local machine to server

```shell
scp ./sourceFile root@OUR_IP_ADDRESS:/root/destinationPath/
```

## Ubuntu

```shell
# Process list
top
# Free memory check
free
```

## Docker

```shell
# Containers
docker container ls
docker ps --all
docker rm containerHash

# Images
docker images
docker rmi imageHash

# Volumes
docker volume ls
docker volume rm volumeName

# Shell of a container
 docker exec -it containerHash sh

# Logs of a container
docker exec -it containerHash sh
```

## Docker compose

Find the Docker release assets from https://github.com/docker/compose/releases. Use the right URL based on the OS and architecture.

```shell
sudo curl -L "https://github.com/docker/compose/releases/download/v2.29.2/docker-compose-linux-aarch64" -o /usr/local/bin/docker-compose

sudo chmod +x /usr/local/bin/docker-compose

sudo docker-compose --version
```

## nginx proxy manager

https://nginxproxymanager.com/guide/

### Installation using Docker compose

Use the `nginx/docker-compose.yml` and copy it to `/root/nginx` in the server using `scp`

```shell
docker-compose up -d
```

- `OUR_IP_ADDRESS:80` should show a "Congratulations!" page.
- `OUR_IP_ADDRESS:81` should open the admin panel.

## Uptime Kuma

https://github.com/louislam/uptime-kuma

### Installation using Docker

### Option 1

```shell
docker run -d --restart=always -p 127.0.0.1:3001:3001 -v uptime-kuma:/app/data --name uptime-kuma louislam/uptime-kuma:1
```

OR

### Option 2

Use the `uptime-kuma/docker-compose.yml` and copy it to `/root/uptime-kuma` in the server using `scp`

```shell
docker-compose up -d
```

### Post installation

One of the above commands does not expose the application to an external port
and is secure. Requests would be handled by nginx proxy manager instead of
directly sending to the server from external networks.

### Cloudflare DNS setup

- Create a Cloudflare account and associate your domain with the Cloudflare dns
  servers.
- Set your A and AAAA record such that they point to your IPv4 and IPv6 of your
  VPS server. Also create a CNAME record called "www" with your domain as target. All these records are proxied.
- Create a third CNAME called "uptime" or your desired addressed such that
  `uptime.domain.com` is the webpage of Uptime-Kuma. Choose a non-proxied status for this record.

### Nginx configuration

Create a new Proxy Host with these details:

- Domain Names: uptime.domain.com
- Scheme: http
- Forward Hostname / IP: "uptime-kuma" (Virtual Docker network IP name)
- Forward Port: "3001"
- "Block Common Exploits" and "Websockets support" checked.

## Portainer

https://github.com/portainer/portainer

### Installation using Docker

Use the `portainer/docker-compose.yml` and copy it to `/root/portainer` in the server using `scp`

```shell
docker-compose up -d
```

### Post installation

The above command exposes the application to an external port 9443 and could
pose a risk. Requests would be proxied by nginx proxy manager instead of
directly sending it to the server from external networks.

### Cloudflare DNS setup

- Create a Cloudflare account and associate your domain with the Cloudflare dns
  servers.
- Set your A and AAAA record such that they point to your IPv4 and IPv6 of your
  VPS server. Also create a CNAME record called "www" with your domain as target. All these records are proxied.
- Create a third CNAME called "portainer" or your desired addressed such that
  `portainer.domain.com` is the webpage of Portainer. Choose a non-proxied status for this record.

### Nginx configuration

Create a new Proxy Host with these details:

- Domain Names: portainer.domain.com
- Scheme: https
- Forward Hostname / IP: IP address of the VPS server
- Forward Port: "9443"
- "Block Common Exploits" checked.

## Hosting a static site

### Copy static site files

Using `scp`, copy the static site files into the directory where we want to run
the nginx alpine web server. This directory should contain the `index.html` or
equivalent file to serve the website.

Example: `dist/*` to `/root/nginx/astro-site/*`

### Installation using Docker

Use the `static-site/docker-compose.yml` and copy it to `/root/static-site` in
the server using `scp`. Optionally keep one `docker-compose.yml` file for all
the containers.

```shell
docker-compose up -d
```

### Cloudflare DNS setup

- Follow previous advice on Cloudflare setup.
- Create a new CNAME called "me" or your desired name for the static site such
  that `me.domain.com` is the website URL. Choose a non-proxied status for this
  record.

### Nginx configuration

Create a new Proxy Host with these details:

- Domain Names: me.domain.com
- Scheme: http
- Forward Hostname / IP: "my-static-site" (Virtual Docker network IP name)
- Forward Port: "80"
- "Block Common Exploits" checked.

## Fail2Ban

https://github.com/fail2ban/fail2ban

### Installation using Docker

Use the `fail2ban/docker-compose.yml` and copy it to `/root/fail2ban` in the server using `scp`

```shell
docker-compose up -d
```

### Getting Real IPs from CloudFlare

Since we use Cloudflare, we do not always get Real IPs of offending users. In
order to not block Cloudfare IPs, we want to obtain the Real IPs of users.

Using the nginx proxy manager console, We need to Edit all the Proxy hosts and
add the following in the "Advanced" configuration.

```
real_ip_header CF-Connecting-IP;
```

This ensures we ban the correct IPs.

### Configure Fail2Ban

Once the container is up, we will find a `data` directory under
`/root/fail2ban`.

- Open `action.d/cloudflare-apiv4.conf` and update `cfuser` and `cftoken`. This
  token can be obtained from the Cloudflare dashboard.
- Open `jail.d/npm.local` and replace "Personal IP address" with your actual IP
  address to whitelist this IP from all bans.

Using `scp`, copy all the files under `action.d`, `filter.d` and `jail.d` into
the `data` directory in the server.

### Restart Fail2Ban

```shell
docker-compose down
docker-compose up -d
```

Run these commands to restart the container to use the new configuration above.

## CTOP in Docker

https://github.com/bcicen/ctop

```shell
docker run --rm -ti \
 --name=ctop \
 --volume /var/run/docker.sock:/var/run/docker.sock:ro \
 andreasmueller/ctop
```
