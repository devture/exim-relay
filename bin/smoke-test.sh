#!/usr/bin/env bash

# Starts the given image and checks that Exim accepts its configuration and
# answers SMTP connections.
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

docker run -d --name "$container" -p 127.0.0.1::8025 "$image" > /dev/null
port="$(docker port "$container" 8025/tcp | head -n1 | sed -E 's|^.*:||')"

# Exim may take a moment to start listening.
listening=false
for _ in $(seq 1 30); do
	if (: < "/dev/tcp/127.0.0.1/$port") 2> /dev/null; then
		listening=true
		break
	fi
	sleep 1
done

if [ "$listening" != true ]; then
	echo >&2 "Exim is not listening on port 8025"
	docker logs "$container" >&2
	exit 1
fi

exec 3<> "/dev/tcp/127.0.0.1/$port"

expect() {
	local code="$1"
	local line
	# Multi-line replies (`250-...`) end with a `250 ...` line.
	while IFS= read -r -t 10 line <&3; do
		echo "< ${line%$'\r'}"
		case "$line" in
			"$code "*) return 0 ;;
			"$code-"*) continue ;;
			*) break ;;
		esac
	done
	echo >&2 "Expected an SMTP $code reply"
	docker logs "$container" >&2
	exit 1
}

send() {
	echo "> $1"
	printf '%s\r\n' "$1" >&3
}

expect 220
send 'EHLO smoke-test.example.com'
expect 250
send 'QUIT'
expect 221

exec 3>&-
echo "Smoke test passed"
