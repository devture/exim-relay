FROM alpine:3.6

RUN apk --no-cache add exim && \
    mkdir /var/log/exim /var/spool/exim /usr/lib/exim && \
    ln -sf /dev/stdout /var/log/exim/mainlog && \
    ln -sf /dev/stderr /var/log/exim/panic && \
    ln -sf /dev/stderr /var/log/exim/reject && \
    chown -R exim:exim /var/log/exim /var/spool/exim /usr/lib/exim && \
    chmod 0755 /usr/sbin/exim

COPY exim.conf /etc/exim/exim.conf

USER exim
EXPOSE 10025

ENV LOCAL_DOMAINS=@ \
    RELAY_FROM_HOSTS=10.0.0.0/8:172.16.0.0/12:192.168.0.0/16 \
    RELAY_TO_DOMAINS=* \
    SMARTHOST= \
    SMTP_USERNAME= \
    SMTP_PASSWORD=

ENTRYPOINT ["exim", "-bdf", "-q15m"]
