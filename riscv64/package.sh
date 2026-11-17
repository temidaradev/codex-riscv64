#!/usr/bin/env bash
# Cross-build Codex for riscv64 and assemble an official-layout package tarball.
# Usage: riscv64/package.sh <codex checkout> <version> <out dir>
# Needs rustup, zig and cargo-zigbuild. rg and bwrap are added on the device by install.sh.
set -euo pipefail
SRC=$(cd "$1" && pwd); VERSION=$2; OUT=$(mkdir -p "$3" && cd "$3" && pwd)
HERE=$(cd "$(dirname "$0")" && pwd)
TARGET=riscv64gc-unknown-linux-gnu
GLIBC=${GLIBC:-2.36}

python3 "$HERE/apply-patches.py" "$SRC" "$VERSION"
cd "$SRC/codex-rs"
rustup target add "$TARGET" >/dev/null
CARGO_PROFILE_RELEASE_DEBUG=${CARGO_PROFILE_RELEASE_DEBUG:-0} \
  cargo zigbuild --release --target "$TARGET.$GLIBC" \
  -p codex-cli --bin codex -p codex-exec-server-cli --bin codex-exec-server

BIN=target/$TARGET/release
rustup component add llvm-tools >/dev/null
STRIP=$(ls "$(rustc --print sysroot)"/lib/rustlib/*/bin/llvm-strip | head -1)
NAME=codex-$VERSION-$TARGET
PKG=$(mktemp -d)/$NAME
mkdir -p "$PKG/bin" "$PKG/codex-resources" "$PKG/codex-path"
for b in codex codex-exec-server; do
  "$STRIP" -o "$PKG/bin/$b" "$BIN/$b"
done
# Code mode needs V8, which has no riscv64 build. Codex falls back to direct tools when this fails.
cat > "$PKG/bin/codex-code-mode-host" <<'STUB'
#!/bin/sh
echo "codex-code-mode-host: code mode is unavailable on riscv64 (no V8 build)" >&2
exit 1
STUB
chmod 755 "$PKG/bin/"*
cat > "$PKG/codex-package.json" <<JSON
{
  "layoutVersion": 1,
  "version": "$VERSION",
  "target": "$TARGET",
  "variant": "codex",
  "entrypoint": "bin/codex",
  "execServer": "bin/codex-exec-server",
  "resourcesDir": "codex-resources",
  "pathDir": "codex-path"
}
JSON
tar -C "$(dirname "$PKG")" -czf "$OUT/$NAME.tar.gz" "$NAME"
(cd "$OUT" && shasum -a 256 "$NAME.tar.gz" > "$NAME.tar.gz.sha256")
ls -la "$OUT/$NAME.tar.gz"
