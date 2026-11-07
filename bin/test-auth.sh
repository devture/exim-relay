#!/usr/bin/env bash
# Tests inbound TLS + SMTP AUTH of the built image.
# Usage: bin/test-auth.sh IMAGE
#
# Works on GitHub runners and in `act`: it never bind-mounts host paths and
# never publishes ports (both break when the docker CLI runs inside another
# container). Files are injected with `docker cp`, and the SMTP client runs in
# a container sharing the exim container's network namespace.
set -euo pipefail

IMAGE="${1:?usage: $0 IMAGE}"
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
NAME="exim-auth-test-$$"
PYIMAGE="${PYIMAGE:-docker.io/python:3-alpine}"

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$TMP"; }
trap cleanup EXIT

echo "== config parses"
docker run --rm "$IMAGE" exim -bV >/dev/null

openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=localhost" \
  -keyout "$TMP/test.key" -out "$TMP/test.crt" 2>/dev/null
printf 'smtpuser:%s\n' "$(openssl passwd -6 'S3cret')" > "$TMP/test.users"
chmod 644 "$TMP"/test.*   # must be readable by the (non-root) exim user

# start SCENARIO_FILES RELAY_FROM_HOSTS [AUTH_ALLOW_INSECURE]
#   SCENARIO_FILES: space separated subset of "cert key users"
start() {
  local files="$1" relay="$2" insecure="${3:-no}" f
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker create --name "$NAME" \
    -e HOSTNAME=relay.test \
    -e DISABLE_SENDER_VERIFICATION=1 \
    -e SMARTHOST=192.0.2.1::25 \
    -e RELAY_FROM_HOSTS="$relay" \
    -e TLS_CERT_FILE=/etc/exim/test.crt \
    -e TLS_KEY_FILE=/etc/exim/test.key \
    -e AUTH_USERS_FILE=/etc/exim/test.users \
    -e AUTH_ALLOW_INSECURE="$insecure" \
    "$IMAGE" >/dev/null
  for f in $files; do
    case "$f" in
      cert)  docker cp "$TMP/test.crt" "$NAME:/etc/exim/test.crt" ;;
      key)   docker cp "$TMP/test.key" "$NAME:/etc/exim/test.key" ;;
      users) docker cp "$TMP/test.users" "$NAME:/etc/exim/test.users" ;;
    esac
  done
  docker start "$NAME" >/dev/null
}

run_check() {
  echo "== $1"
  if ! docker run --rm -i --network "container:$NAME" "$PYIMAGE" python3 - "$1" \
    < "$HERE/smtp_check.py"; then
    echo "--- exim log of the container under test:" >&2
    docker logs "$NAME" >&2 || true
    exit 1
  fi
}

# Route recipient verification through a TEST-NET smarthost so these RCPT
# checks do not need DNS. No DATA is sent, so no delivery is attempted.
# The client connects from 127.0.0.1 (shared network namespace).
start ""               "<; 127.0.0.0/8";   run_check trusted
start "cert key users" "<; 127.0.0.0/8";   run_check trusted
start "cert key users" "<; 203.0.113.0/24"; run_check untrusted
start "cert key"       "<; 203.0.113.0/24"; run_check noauth
start "users"          "<; 203.0.113.0/24"; run_check notls
start "cert users"     "<; 203.0.113.0/24"; run_check notls
start "key users"      "<; 203.0.113.0/24"; run_check notls
start "users"          "<; 203.0.113.0/24" yes; run_check insecure
start ""               "<; 203.0.113.0/24" yes; run_check notls

echo "All auth/TLS checks passed"
