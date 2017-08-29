# Docker Exim Relay Image

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0) [![Layers](https://images.microbadger.com/badges/image/industrieco/exim-relay.svg)](https://microbadger.com/images/industrieco/exim-relay/) [![GitHub Tag](https://img.shields.io/github/tag/industrieco/docker-exim-relay.svg)](https://registry.hub.docker.com/u/industrieco/docker-exim-relay/) [![Docker Pulls](https://img.shields.io/docker/pulls/industrieco/exim-relay.svg)](https://registry.hub.docker.com/u/industrieco/exim-relay/)

A light weight Docker image for an Exim mail relay, based on the official Alpine image.

For extra security, the container runs as exim not root.

## Docker

### Default setup

This will allow relay from all private address ranges and will relay directly to the internet receiving mail servers

```
docker run \
       --name smtp \
       --restart always \
       -h my.host.name \
       -d \
       -p 25:8025 \
       industrieco/exim-relay
```

### Smarthost setup

To send forward outgoing email to a smart relay host

```
docker run \
       --restart always \
       -h my.host.name \
       -d \
       -p 25:8025 \
       -e SMARTHOST=some.relayhost.name \
       -e SMTP_USERNAME=someuser \
       -e SMTP_PASSWORD=password \
       industrieco/exim-relay
```

## Docker Compose

```
version: "2"
  services:
    smtp:
      image: industrieco/exim-relay
      restart: always
      ports:
        - "25:8025"
      hostname: my.host.name
      environment:
        - SMARTHOST=some.relayhost.name
        - SMTP_USERNAME=someuser
        - SMTP_PASSWORD=password
```

## Other Variables

###### LOCAL_DOMAINS

* List (colon separated) of domains that are delivered to the local machine
* Defaults to the hostname of the local machine
* Set blank to have no mail delivered locally

###### RELAY_FROM_HOSTS

* A list (colon separated) of subnets to allow relay from
* Set to "\*" to allow any host to relay - use this with RELAY_TO_DOMAINS to allow any client to relay to a list of domains
* Defaults to private address ranges: 10.0.0.0/8:172.16.0.0/12:192.168.0.0/16

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

###### SMARTHOST

* A relay host to forward all non-local email through

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
