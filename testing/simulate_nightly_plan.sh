#!/usr/bin/env bash
# Simulation of tool/nightly_plan.sh with a stub `gh`: three nights in a row.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
cat > "$work/bin/gh" <<'GH'
#!/usr/bin/env bash
# `gh release view <tag> --json body -q .body`: print $FAKE_BODY, or fail like a missing release.
[ -n "${FAKE_RELEASE:-}" ] || { echo "release not found" >&2; exit 1; }
printf '%s\n' "$FAKE_BODY"
GH
chmod +x "$work/bin/gh"
cd "$here"
run() { echo "--- $1"; env PATH="$work/bin:$PATH" "${@:2}" bash tool/nightly_plan.sh "$SHA" 2>&1; }

SHA=aaaaaaa1111111111111111111111111111111aa
run "night 1: no nightly release exists yet"
run "night 2: nightly exists but for an older commit" FAKE_RELEASE=1 FAKE_BODY="Nightly build of commit bbbbbbb22222222222222222222222222222bbbb."
run "night 3: nightly already built from this commit (no new commits)" FAKE_RELEASE=1 FAKE_BODY="Nightly build of commit $SHA. Built automatically."
