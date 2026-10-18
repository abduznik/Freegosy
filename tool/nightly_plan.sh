#!/usr/bin/env bash
# Decides whether a nightly build is due for the commit given as $1.
# Prints `build=true|false` and `tag=<nightly tag>` (for $GITHUB_OUTPUT).
# The nightly release body names the commit it was built from, so a failed
# build leaves no body and is retried the next night.
set -eu
sha="${1:?usage: nightly_plan.sh <commit sha>}"
# One rolling release, always overwritten, with no version of its own.
tag="nightly"
body=$(gh release view "$tag" --json body -q .body 2>/dev/null || true)
if [ -n "$body" ] && printf '%s' "$body" | grep -qF "$sha"; then
  echo "A nightly for ${sha:0:7} already exists; nothing to build." >&2
  echo "build=false"
else
  echo "Nightly for ${sha:0:7} is due." >&2
  echo "build=true"
fi
echo "tag=$tag"
