#!/usr/bin/env bash

# Prints the version of the `exim` package (e.g. `4.99.5-r0`) that the base
# image of the Dockerfile currently offers.
#
# Alpine only keeps the latest revision of each package, so the result can
# change over time even if the Dockerfile does not.
# Passing it to the build as `EXIM_VERSION` makes the image contain exactly
# this version (or fail to build), so that it can be tagged ahead of time.
#
# Usage: bin/resolve-exim-version.sh

set -euo pipefail

repository_path="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

base_image="$(sed -nE 's|^FROM[[:space:]]+([^[:space:]]+).*$|\1|p' "$repository_path/Dockerfile" | head -n1)"

if [ -z "$base_image" ]; then
	echo >&2 "Could not determine the base image from the Dockerfile"
	exit 1
fi

package="$(docker run --rm "$base_image" sh -c 'apk update -q > /dev/null && apk search -x exim')"
version="${package#exim-}"

if ! [[ "$version" =~ ^[0-9][0-9.]*-r[0-9]+$ ]]; then
	echo >&2 "Unexpected exim package in $base_image: $package"
	exit 1
fi

echo "$version"
