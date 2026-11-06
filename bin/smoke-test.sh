#!/usr/bin/env bash

# Starts the given image and checks that Exim accepts its configuration and
# answers SMTP connections.
#
# The SMTP conversation happens inside the container (BusyBox `nc`) instead of
# over a published port. That way the test also works when the docker CLI does
# not share a network with the docker daemon's host (`act`, remote daemons,
# Docker-in-Docker), where `localhost:<published port>` is unreachable.
#
# Usage: bin/smoke-test.sh <image>

set -euo pipefail

image="${1:?Usage: $0 <image>}"
container="exim-relay-smoke-test-$$"

cleanup() {
	docker rm -f "$container" > /dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Exim version and configuration check:"
docker run --rm --entrypoint exim "$image" -bV

docker run -d --name "$container" "$image" > /dev/null

# One complete SMTP conversation, run from inside the container.
# The pauses give Exim time to answer before the next command / EOF.
converse() {
	{
		printf 'EHLO smoke-test.example.com\r\n'
		sleep 1
		printf 'QUIT\r\n'
		sleep 1
	} | docker exec -i "$container" nc -w 5 127.0.0.1 8025 2> /dev/null | tr -d '\r' || true
}

# Exim may take a moment to start listening, so retry.
reply=""
for _ in $(seq 1 30); do
	reply="$(converse)"
	if grep -q '^220 ' <<< "$reply" && grep -q '^250 ' <<< "$reply" && grep -q '^221 ' <<< "$reply"; then
		sed 's/^/< /' <<< "$reply"
		echo "Smoke test passed"
		exit 0
	fi
	sleep 1
done

echo >&2 "Exim did not answer the SMTP conversation as expected. Last reply:"
echo >&2 "$reply"
docker logs "$container" >&2
exit 1
