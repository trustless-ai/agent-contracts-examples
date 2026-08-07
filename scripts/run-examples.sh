#!/usr/bin/env bash
#
# Run every example's forge suite.
#
# CI calls this, and so can you: ./scripts/run-examples.sh
#
# Kept free of bash-4-only builtins (mapfile, associative arrays) so it runs
# identically on the macOS bash 3.2 most contributors have and on the runner.
# A CI script that can only be exercised by pushing is a skip path of its own.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# Projects are DISCOVERED, not enumerated. Adding an example wires it into CI
# automatically; a hardcoded list would let a new example land silently
# unchecked, which is the failure mode this script exists to close.
PROJECTS=$(
  find . -name foundry.toml \
    -not -path "./.git/*" \
    -not -path "*/lib/*" \
    | xargs -n1 dirname \
    | sort
)

COUNT=$(printf '%s\n' "$PROJECTS" | grep -c '[^[:space:]]' || true)

# Discovery finding nothing must fail loudly. Otherwise a moved path makes this
# job vacuously green, and CI reporting a pass for checks it never ran is the
# exact shape being guarded against.
if [ "$COUNT" -eq 0 ]; then
  echo "ERROR: no foundry.toml found. Discovery is broken — refusing to report a pass." >&2
  exit 1
fi

echo "Discovered $COUNT example project(s):"
printf '%s\n' "$PROJECTS" | sed 's/^/  /'
echo

FAILED=""
while IFS= read -r DIR; do
  [ -n "$DIR" ] || continue
  echo "──────── $DIR"
  (
    cd "$DIR" || exit 1
    # forge-std is the only dependency and lib/ is gitignored, so a clean
    # checkout has to fetch it before the suite can compile.
    if [ ! -d lib/forge-std ]; then
      forge install foundry-rs/forge-std --no-git >/dev/null 2>&1 \
        || forge install foundry-rs/forge-std >/dev/null 2>&1
    fi
    forge test -vv
  ) || FAILED="$FAILED $DIR"
  echo
done <<EOF
$PROJECTS
EOF

if [ -n "$FAILED" ]; then
  echo "ERROR: failing example(s):$FAILED" >&2
  exit 1
fi

echo "All $COUNT example suite(s) passed."
