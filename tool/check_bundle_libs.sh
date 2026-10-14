#!/usr/bin/env bash
# Fails if the Linux bundle's binary or any bundled .so needs a shared library
# that neither the bundle's lib/ dir nor the host provides. Run on the build
# image: anything unresolved there is missing on users' machines too (#75).
set -u
bundle="${1:?usage: check_bundle_libs.sh <bundle-dir>}"
export LD_LIBRARY_PATH="$bundle/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

status=0
for target in "$bundle"/freegosy "$bundle"/lib/*.so*; do
  [ -f "$target" ] || continue
  missing=$(ldd "$target" 2>&1 | grep 'not found')
  if [ -n "$missing" ]; then
    echo "::error::$(basename "$target") has unresolved libraries:"
    echo "$missing"
    status=1
  fi
done
[ "$status" -eq 0 ] && echo "bundle OK: all shared libraries resolve"
exit "$status"
