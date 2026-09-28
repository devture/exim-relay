FROM docker.io/alpine:3.24.2

# The exact `exim` package version to install (e.g. `4.99.5-r0`), as printed by `bin/resolve-exim-version.sh`.
# CI always passes it, so that the image tag can be determined before building.
# Left empty, the latest available version gets installed.
ARG EXIM_VERSION=

RUN apk --no-cache add "exim${EXIM_VERSION:+=$EXIM_VERSION}" tini && \
    mkdir /var/spool/exim && \
    chmod 777 /var/spool/exim && \
    ln -sf /dev/stdout /var/log/exim/mainlog && \
    ln -sf /dev/stderr /var/log/exim/panic && \
    ln -sf /dev/stderr /var/log/exim/reject && \
    chmod 0755 /usr/sbin/exim

COPY exim.conf /etc/exim/exim.conf

# Regardless of the permissions of the original `exim.conf` file in the build context,
# ensure that the `/etc/exim/exim.conf` configuration file is not writable by the Exim user.
# Otherwise, we'll get an Exim panic:
# > Exim configuration file /etc/exim/exim.conf has the wrong owner, group, or mode
RUN chmod 664 /etc/exim/exim.conf

USER exim
EXPOSE 8025

ENV LOCAL_DOMAINS=@ \
    RELAY_FROM_HOSTS="<; 10.0.0.0/8; 172.16.0.0/12; 192.168.0.0/16; fc00::/7" \
    RELAY_TO_DOMAINS=* \
    RELAY_TO_USERS= \
    DISABLE_SENDER_VERIFICATION= \
    DKIM_SELECTOR=default \
    HOSTNAME= \
    SMARTHOST= \
    SMTP_PASSWORD= \
    SMTP_USERDOMAIN= \
    SMTP_USERNAME=

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["exim", "-bdf", "-q15m"]
