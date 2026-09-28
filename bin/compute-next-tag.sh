#!/usr/bin/env bash

# Prints the tag that the currently checked out commit should be released as,
# or nothing at all if it does not warrant a release.
#
# Usage: bin/compute-next-tag.sh <exim version>
#
# The exim version is the exact `exim` package version the image gets built
# with (e.g. `4.99.5-r0`, as printed by `bin/resolve-exim-version.sh`).
# Tags look like `<exim version>-<release>`:
#
# - if this exim version has never been released, the release counter
#   restarts at 0 (`4.99.5-r0-0`)
# - otherwise the counter is incremented (`4.99.5-r0-1`), but only if something
#   that ends up in the image has changed since the last release
#
# Not tagging when nothing has changed is what lets this run on a schedule:
# it only releases when Alpine starts offering a new exim package.

set -euo pipefail

version="${1:?Usage: $0 <exim version>}"

repository_path="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$repository_path"

# Paths that shape the image. A commit touching only other paths (a README fix,
# CI configuration, helper scripts) produces the same image, and releasing it
# would only create churn for everyone consuming the image.
image_defining_paths=(
	'Dockerfile'
	'exim.conf'
)

tag_prefix="${version}-"

# Of all releases of this version, the highest release number. Sorted
# numerically, so that -10 is recognized as newer than -9. The grep ignores
# any tag which merely starts like this version's tags, but does not end in a
# plain release number.
last_release="$(git tag --list "${tag_prefix}*" | sed -e "s|^${tag_prefix}||" | grep -E '^[0-9]+$' | sort -n | tail -n1 || true)"

if [ -z "$last_release" ]; then
	echo >&2 "Version $version has never been released"
	echo "${tag_prefix}0"
	exit 0
fi

previous_tag="${tag_prefix}${last_release}"

if git diff --quiet "$previous_tag" HEAD -- "${image_defining_paths[@]}"; then
	echo >&2 "Nothing affecting the image has changed since $previous_tag"
	exit 0
fi

echo >&2 "The image has changed since $previous_tag"
echo "${tag_prefix}$((last_release + 1))"
