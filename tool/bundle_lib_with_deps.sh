#!/usr/bin/env bash
# Copies a shared library into a bundle's lib/ dir together with everything it
# needs that a minimal host may lack, so the bundle never relies on the host
# for them. Bundling libsecret alone left its own dependency libgcrypt.so.20
# unresolved on NixOS, where the app then refused to start (#219).
#
# usage: bundle_lib_with_deps.sh <bundle-dir> <soname> [<soname>...]
#
# Not bundled (the host or the GTK/glib stack always provides them): glibc,
# the compiler runtime and glib's own closure.
set -eu
bundle="${1:?usage: bundle_lib_with_deps.sh <bundle-dir> <soname>...}"
shift
dest="$bundle/lib"
mkdir -p "$dest"

skip='^(ld-linux.*|linux-vdso.*|libc|libm|libdl|libpthread|librt|libresolv|libutil|libnsl|libgcc_s|libstdc\+\+|libglib-2\.0|libgobject-2\.0|libgio-2\.0|libgmodule-2\.0|libgthread-2\.0|libpcre2-8|libpcre|libffi|libmount|libblkid|libselinux|libz)\.so'

declare -A seen=()

bundle_one() {
  local soname="$1"
  [[ -n "${seen[$soname]:-}" ]] && return 0
  seen[$soname]=1
  if [[ "$soname" =~ $skip ]]; then return 0; fi

  local path
  path=$(ldconfig -p | grep -F "$soname " | grep -F 'x86-64' | awk '{print $NF}' | head -n 1)
  [[ -z "$path" ]] && path=$(ldconfig -p | grep -F "$soname " | awk '{print $NF}' | head -n 1)
  if [[ -z "$path" ]]; then
    echo "::error::$soname not found on the build image; cannot bundle it"
    return 1
  fi

  if [[ ! -f "$dest/$soname" ]]; then
    cp -L "$path" "$dest/$soname"
    echo "bundled $soname (from $path)"
  fi

  local dep
  while read -r dep; do
    bundle_one "$dep"
  done < <(readelf -d "$path" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p')
}

for lib in "$@"; do
  bundle_one "$lib"
done
