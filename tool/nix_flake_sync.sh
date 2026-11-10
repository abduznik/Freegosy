#!/usr/bin/env bash
# Points flake.nix at the newest stable release and the digest GitHub reports
# for its AppImage, so the flake can't drift from what is actually published
# (#203: the release was re-uploaded after the hash was set). Exits 0 whether or
# not it changed anything; prints `changed=true|false` for $GITHUB_OUTPUT.
# Needs: gh, jq, xxd, base64.
set -eu
repo="${GITHUB_REPOSITORY:-abduznik/Freegosy}"
flake="${1:-flake.nix}"
asset="Freegosy-linux-x86_64.AppImage"

# Newest published stable release that carries the AppImage and a digest.
row=$(gh api "repos/$repo/releases?per_page=30" --jq "
  [.[] | select(.prerelease == false and .draft == false)
       | {tag: .tag_name, digest: (.assets[] | select(.name == \"$asset\") | .digest)}
       | select(.digest != null)] | first | \"\(.tag) \(.digest)\"")
if [ -z "$row" ] || [ "$row" = "null null" ]; then
  echo "No stable release with a $asset digest found" >&2
  echo "changed=false"
  exit 0
fi
tag="${row% *}"
hex="${row#* }"
hex="${hex#sha256:}"
version="${tag#v}"
sri="sha256-$(printf '%s' "$hex" | xxd -r -p | base64)"

current_hash=$(sed -n 's/^ *hash = "\(.*\)";/\1/p' "$flake" | head -n 1)
current_version=$(sed -n 's/^ *version = "\(.*\)";/\1/p' "$flake" | head -n 1)
if [ "$current_hash" = "$sri" ] && [ "$current_version" = "$version" ]; then
  echo "flake.nix already matches $tag ($sri)" >&2
  echo "changed=false"
else
  echo "flake.nix has $current_version / $current_hash; $tag is $sri" >&2
  sed -i "s|^\( *\)hash = \".*\";|\1hash = \"$sri\";|; s|^\( *\)version = \".*\";|\1version = \"$version\";|" "$flake"
  echo "changed=true"
fi
echo "tag=$tag"
