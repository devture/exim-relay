# Docker Exim Relay Image

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0) [![GitHub Tag](https://img.shields.io/github/tag/devture/exim-relay.svg)](https://github.com/devture/exim-relay/pkgs/container/exim-relay/versions)

A lightweight Docker image for an [Exim](https://www.exim.org/) mail relay, based on the official Alpine image.

For extra security, the container runs as exim (`uid=100` and `gid=101`), not root.

This is a fork of [Industrie&Co](https://github.com/industrieco)'s wonderful (but seemingly unmaintained) [industrieco/docker-exim-relay](https://github.com/industrieco/docker-exim-relay) image.
The following changes have been done on top of it:

- based on a newer Alpine release (and thus, newer exim)

- removing Received headers for mail received by exim (helps email deliverability)


## Docker

### Default setup

This will allow relay from all private address ranges and will relay directly to the internet receiving mail servers

```
docker run \
       --user=100:101 \
       --name smtp \
       --restart always \
       -e HOSTNAME=my.host.name \
       -d \
       -p 25:8025 \
       ghcr.io/devture/exim-relay:SOME_TAGGED_RELEASE
```

**Note**: we advise setting the hostname using a `HOSTNAME` environment variable, instead of `--hostname`. Since Docker 20.10, the latter has the side-effect of making other services on the same Docker network resolve said hostname to the in-container IP address of the mailer container. If you'd rather this hostname resolves to the actual public IP address, avoid using `--hostname`.


### Smarthost setup

To send forward outgoing email to a smart relay host

```
docker run \
       --user=100:101 \
       --name smtp \
       --restart always \
       -d \
       -p 25:8025 \
       -e HOSTNAME=my.host.name \
       -e SMARTHOST=some.relayhost.name::587 \
       -e SMTP_USERNAME=someuser \
       -e SMTP_PASSWORD=password \
       ghcr.io/devture/exim-relay:SOME_TAGGED_RELEASE
```

### Smarthost setup with implicit TLS (SMTPS, port 465)

For providers that require implicit TLS instead of STARTTLS ([RFC 8314](https://www.rfc-editor.org/rfc/rfc8314)):

```
docker run \
       --user=100:101 \
       --name smtp \
       --restart always \
       -d \
       -p 25:8025 \
       -e HOSTNAME=my.host.name \
       -e SMARTHOST=some.relayhost.name::465 \
       -e SMARTHOST_PROTOCOL=smtps \
       -e SMTP_USERNAME=someuser \
       -e SMTP_PASSWORD=password \
       ghcr.io/devture/exim-relay:SOME_TAGGED_RELEASE
```

### DKIM setup

To sign outgoing email with DKIM

```
docker run \
       --user=100:101 \
       --name smtp \
       --restart always \
       -d \
       -p 25:8025 \
       -e HOSTNAME=my.host.name \
       -e SMARTHOST=some.relayhost.name::587 \
       -e SMTP_USERNAME=someuser \
       -e SMTP_PASSWORD=password \
       --mount type=bind,src=/PATH/TO/THE/PRIVATE/KEY.pem,dst=/etc/exim/dkim.pem,ro \
       ghcr.io/devture/exim-relay:SOME_TAGGED_RELEASE
```

You can adjust the [DKIM selector](https://dmarcly.com/blog/what-is-dkim-selector-and-how-does-it-work-dkim-selector-explained) value by passing an additional `DKIM_SELECTOR` environment variable. By default, it has a value of `default`.

### Inbound SMTP AUTH and TLS (some clients log in, others don't)

By default, any client in `RELAY_FROM_HOSTS` can relay **without** logging in (the default covers all private ranges).
Clients outside that list are rejected, unless they authenticate via SMTP AUTH (`LOGIN` / `PLAIN`).

To let some networks send without a password and require a login from everyone else:

1. Restrict `RELAY_FROM_HOSTS` to the networks that may send without logging in.
2. Provide a users file (`AUTH_USERS_FILE`) with `username:hash` lines.
3. Provide a TLS certificate and key (`TLS_CERT_FILE` / `TLS_KEY_FILE`). By default, AUTH is only offered over TLS (STARTTLS).

Generate a password hash (any `crypt(3)` hash supported by musl works, e.g. SHA-512):

```
docker run --rm -it alpine sh -c 'apk add --no-cache -q openssl && openssl passwd -6'
```

Users file:

```
smtpuser:$6$salt$hash...
```

Docker example:

```
docker secret create EXIM_USERS ./exim_users
docker secret create TLS_CERT ./fullchain.pem
docker secret create TLS_KEY ./privkey.pem

docker service create --name exim-relay --mode global \
  --publish mode=host,target=8025,published=25 \
  --secret source=EXIM_USERS,target=EXIM_USERS,uid=100,gid=101,mode=0400 \
  --secret source=TLS_CERT,target=TLS_CERT,uid=100,gid=101,mode=0444 \
  --secret source=TLS_KEY,target=TLS_KEY,uid=100,gid=101,mode=0400 \
  -e TLS_CERT_FILE=/run/secrets/TLS_CERT \
  -e TLS_KEY_FILE=/run/secrets/TLS_KEY \
  -e HOSTNAME=my.host.name \
  -e RELAY_FROM_HOSTS="<; 10.10.0.0/16; 192.168.50.0/24" \
  ghcr.io/devture/exim-relay:SOME_TAGGED_RELEASE
```

Docker run example (bind mounts):

```
docker run \
       --user=100:101 \
       -d -p 25:8025 \
       -e HOSTNAME=my.host.name \
       -e RELAY_FROM_HOSTS="<; 10.10.0.0/16" \
       --mount type=bind,src=/PATH/TO/exim_users,dst=/run/secrets/EXIM_USERS,ro \
       --mount type=bind,src=/PATH/TO/fullchain.pem,dst=/etc/exim/tls/tls.crt,ro \
       --mount type=bind,src=/PATH/TO/privkey.pem,dst=/etc/exim/tls/tls.key,ro \
       ghcr.io/devture/exim-relay:SOME_TAGGED_RELEASE
```

Test (from a network that is **not** in `RELAY_FROM_HOSTS`):

```
swaks --server HOST --to someone@example.com --from me@example.com --tls --auth LOGIN --auth-user smtpuser --auth-password 'PASSWORD'
```

Notes:

* If the certificate or key file does not exist, STARTTLS is not offered (and neither is AUTH, unless `AUTH_ALLOW_INSECURE=yes`).
* If the users file does not exist, SMTP AUTH is not offered.
* Authenticated clients may relay to any recipient domain (`RELAY_TO_DOMAINS` only applies to hosts in `RELAY_FROM_HOSTS`).
* The certificate file should contain the full chain. Certificate and key must be readable by the `exim` user (`uid=100`).
* Docker secrets and configs are immutable: to rotate a certificate or the users file, create a new secret and update the service.
* Use `mode=host` when publishing the port in Swarm, otherwise the source IP is lost and `RELAY_FROM_HOSTS` cannot match client addresses.

## Docker Compose

```
version: "3.7"

services:
  smtp:
    image: ghcr.io/devture/exim-relay:SOME_TAGGED_RELEASE
    user: 100:101
    restart: always
    ports:
      - "25:8025"
    environment:
      HOSTNAME: my.host.name
      SMARTHOST: some.relayhost.name::587
      SMTP_USERNAME: someuser
      SMTP_PASSWORD: password
```

## Other Variables

###### HOSTNAME

* The hostname that is sent as part of the `HELO` message.

###### LOCAL_DOMAINS

* List (colon separated) of domains that are delivered to the local machine
* Defaults to the hostname of the local machine
* Set blank to have no mail delivered locally

###### RELAY_FROM_HOSTS

* A list prefixed with `<; `, which contains `;`-separated IPv4/IPv6 subnets to allow relay from (see the default value below for an example)
* Set to "\*" to allow any host to relay - use this with RELAY_TO_DOMAINS to allow any client to relay to a list of domains
* Defaults value: `<; 10.0.0.0/8; 172.16.0.0/12; 192.168.0.0/16; fc00::/7`

💡 Lists in exim use `:` as a value separator by default. Since IPv6 addresses are written with `:` inside them, we override the default separator by adding the `<; ` prefix. This allows for `:` to be used in IP address ranges without being interpreted as a separator.

###### RELAY_TO_DOMAINS

* A list (colon separated) of domains to allow relay to
* Defaults to "\*" to allow relaying to all domains
* Setting both RELAY_FROM_HOSTS and RELAY_TO_DOMAINS to "\*" will make this an open relay
* Setting both RELAY_FROM_HOSTS and RELAY_TO_DOMAINS to other values will limit which clients can send and who they can send to

###### RELAY_TO_USERS

* A whitelist (colon separated) of recipient email addresses to allow relay to
* This list is processed in addition to the domains in RELAY_TO_DOMAINS
* Use this for more precise whitelisting of relayable mail
* Defaults to "" which doesn't whitelist any addresses

###### TLS_CERT_FILE / TLS_KEY_FILE

* Paths to the server certificate (full chain) and private key used for inbound TLS (STARTTLS)
* Defaults: `/etc/exim/tls/tls.crt` and `/etc/exim/tls/tls.key`
* If either file is missing, TLS is not offered to clients

###### AUTH_USERS_FILE

* Path to a file with `username:hash` lines (`crypt(3)` hashes, e.g. `openssl passwd -6`) used for inbound SMTP AUTH (`LOGIN` / `PLAIN`)
* Usernames are matched case-insensitively; names that differ only in letter case refer to the same account
* Default: `/run/secrets/EXIM_USERS` (a Docker secret named `EXIM_USERS`)
* If the file is missing, inbound SMTP AUTH is disabled

###### AUTH_ALLOW_INSECURE

* Set to `yes` to allow SMTP AUTH without TLS (credentials travel in plaintext - not recommended)
* Defaults to `no`: AUTH is only offered after STARTTLS

###### DISABLE_SENDER_VERIFICATION

If the environment variable is set, sender address verification will be disabled.

###### SMARTHOST

* A relay host to forward all non-local email through

###### SMARTHOST_PROTOCOL

* The protocol to use when connecting to the smarthost
* Set to `smtps` for implicit TLS (RFC 8314); use together with port 465 in `SMARTHOST`
* Defaults to `smtp` (STARTTLS)
* Example: `SMARTHOST_PROTOCOL=smtps` together with `SMARTHOST=smtp.example.com::465`

###### SMTP_USERNAME

* The username for authentication to the smarthost

###### SMTP_PASSWORD

* The password for authentication to the smarthost - leave this blank to disable authenticaion


## Docker Secrets

The smarthost password can also be supplied via docker swarm secrets / rancher secrets.  Create a secret called SMTP_PASSWORD and don't use the SMTP_PASSWORD environment variable

## Debugging

The logs are sent to /dev/stdout and /dev/stderr and can be viewed via docker logs

```shell
docker logs smtp
```

```shell
docker logs -f smtp
```

Exim commands can be run to check the status of the mail server as well

```shell
docker exec -ti smtp exim -bp
```
