# Docker Exim Relay Image

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0) [![Layers](https://images.microbadger.com/badges/image/devture/exim-relay.svg)](https://microbadger.com/images/devture/exim-relay/) [![GitHub Tag](https://img.shields.io/github/tag/devture/exim-relay.svg)](https://registry.hub.docker.com/u/devture/exim-relay/) [![Docker Pulls](https://img.shields.io/docker/pulls/devture/exim-relay.svg)](https://registry.hub.docker.com/u/devture/exim-relay/)

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
       --init \
       --restart always \
       -e HOSTNAME=my.host.name \
       -d \
       -p 25:8025 \
       devture/exim-relay
```

**Note**: we advise setting the hostname using a `HOSTNAME` environment variable, instead of `--hostname`. Since Docker 20.10, the latter has the side-effect of making other services on the same Docker network resolve said hostname to the in-container IP address of the mailer container. If you'd rather this hostname resolves to the actual public IP address, avoid using `--hostname`.


### Smarthost setup

To send forward outgoing email to a smart relay host

```
docker run \
       --user=100:101 \
       --name smtp \
       --init \
       --restart always \
       -d \
       -p 25:8025 \
       -e HOSTNAME=my.host.name \
       -e SMARTHOST=some.relayhost.name::587 \
       -e SMTP_USERNAME=someuser \
       -e SMTP_PASSWORD=password \
       devture/exim-relay
```

## Docker Compose

```
version: "3.7"
  services:
    smtp:
      image: devture/exim-relay
      user: 100:101
      init: true
      restart: always
      ports:
        - "25:8025"
      environment:
        HOSTNAME=my.host.name
        SMARTHOST=some.relayhost.name::587
        SMTP_USERNAME=someuser
        SMTP_PASSWORD=password
```

## Other Variables

###### HOSTNAME

* The hostname that is sent as part of the `HELO` message.

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

###### DISABLE_SENDER_VERIFICATION

If the environment variable is set, sender address verification will be disabled.

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

## Helm Chart
The Helm Chart in [helm/exim-relay](helm/exim-relay) can be used to deploy into a Kubernetes cluster.

The Chart will deploy by default 2 pods load balanced with a service and expose port 25.

This can all be configured using the following variables (see also [helm/exim-relay](helm/exim-relay))

### Configuration

The following table lists the configurable parameters of the chart and their default values (see variables section for a description).

| Parameter                  | Variable         | Default  |
| -------------------------- | ---------------- | ----- |
| `relayHost`                | SMARTHOST        | `smtp.example.com::587` |
| `relayHostname`            | HOSTNAME         | `my.host.local`|
| `relayFromHosts`           | RELAY_FROM_HOSTS | `10.0.0.0/8,127.0.0.0/8,172.17.0.0/16,192.0.0.0/8` |
| `relayUsername`            | SMTP_USERNAME    | `relayuser` | 
| `relayPassword`            | SMTP_PASSWORD    | `relaypassword` |
| `relayToDomains`           | RELAY_TO_DOMAINS | `*`|
| `localDomains`             | LOCAL_DOMAINS    | ``|
| `relayToUsers`             | RELAY_TO_USERS   | ``|
| `relayDisableSenderVerification` | DISABLE_SENDER_VERIFICATION | `false` |

