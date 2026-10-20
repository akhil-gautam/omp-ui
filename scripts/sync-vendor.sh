#!/bin/sh
# Refresh vendor/omp-rpc from the upstream oh-my-pi repository.
#
# Usage: scripts/sync-vendor.sh [ref]
#
# The ref defaults to `main`. The Rust 1.87 compatibility patch is re-applied
# afterwards so the crate keeps building with the toolchain omp-ui targets.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VENDOR="$ROOT/vendor/omp-rpc"
UPSTREAM="https://api.github.com/repos/can1357/oh-my-pi/contents/sdk/rust/omp-rpc"
REF="${1:-main}"

rm -rf "$VENDOR/src"
mkdir -p "$VENDOR/src"

for file in Cargo.toml README.md .gitignore; do
	curl -fsSL --max-time 60 -H "Accept: application/vnd.github.raw" \
		"$UPSTREAM/$file?ref=$REF" -o "$VENDOR/$file"
done

for file in lib.rs frame.rs turn.rs client.rs host_tool.rs host_uri.rs wire.rs; do
	curl -fsSL --max-time 120 -H "Accept: application/vnd.github.raw" \
		"$UPSTREAM/src/$file?ref=$REF" -o "$VENDOR/src/$file"
done

# Upstream ships the crate as a standalone workspace; omp-ui's workspace takes
# its place, so the upstream table is dropped.
python3 - "$VENDOR/Cargo.toml" <<'PY'
import re
import sys

path = sys.argv[1]
text = open(path).read()
text = re.sub(r"\n# Standalone crate: not a member of the repository's root workspace\.\n\[workspace\]\n", "\n", text)
open(path, "w").write(text)
PY

patch -p1 -d "$VENDOR" < "$ROOT/vendor/patches/rustc-1.87.patch"

echo "vendor/omp-rpc refreshed from $REF"
