#!/usr/bin/env bash
# Before/after simulation for #75. Builds a stand-in for the Linux bundle with
# the same link chain as the real one (runner -> libzstandard_linux_plugin.so
# -> libzstandard_linux.so), packages it the old way (zstd copied only into the
# AppImage dir, after the tarball) and the new way (zstd copied before
# packaging), then unpacks each tarball into a clean dir and tries to start it.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cd "$work"

mkdir -p build/bundle/lib
echo 'int zstd_stub(void){return 42;}' > zstd.c
echo 'int zstd_stub(void); int plugin_stub(void){return zstd_stub();}' > plugin.c
echo 'int plugin_stub(void); int main(void){return plugin_stub()==42?0:1;}' > main.c
gcc -shared -fPIC zstd.c -o build/libzstandard_linux.so -Wl,-soname,libzstandard_linux.so
gcc -shared -fPIC plugin.c -o build/bundle/lib/libzstandard_linux_plugin.so \
  -Lbuild -lzstandard_linux -Wl,-rpath,'$ORIGIN' -Wl,--no-as-needed
gcc main.c -o build/bundle/freegosy -Lbuild/bundle/lib -l:libzstandard_linux_plugin.so \
  -Wl,-rpath,'$ORIGIN/lib' -Wl,--allow-shlib-undefined

run() { # label, tarball
  mkdir -p "unpack_$1" && tar -xzf "$2" -C "unpack_$1"
  echo "--- $1: checker"
  bash "$here/tool/check_bundle_libs.sh" "unpack_$1" || true
  echo "--- $1: launch (LD_LIBRARY_PATH unset, like the tar.gz on Fedora)"
  if (cd "unpack_$1" && env -u LD_LIBRARY_PATH ./freegosy); then echo "launch OK"; else echo "launch FAILED"; fi
}

# BEFORE: tarball made first, zstd only copied into the AppImage dir afterwards.
(cd build/bundle && tar -czf ../../before.tar.gz .)
run before before.tar.gz

# AFTER: zstd bundled before packaging.
cp -L build/libzstandard_linux.so build/bundle/lib/
(cd build/bundle && tar -czf ../../after.tar.gz .)
run after after.tar.gz
