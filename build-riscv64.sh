#!/usr/bin/env bash
# Cross-compile the Codex CLI for riscv64 Linux (glibc >= 2.36) with cargo-zigbuild.
# Needs: rustup, zig, cargo-zigbuild. Works from macOS or Linux hosts.
set -euo pipefail
cd "$(dirname "$0")/codex-rs"
TARGET=riscv64gc-unknown-linux-gnu
GLIBC=${GLIBC:-2.36}
rustup target add "$TARGET" >/dev/null
cargo zigbuild --release --target "$TARGET.$GLIBC" -p codex-cli --bin codex
OUT=target/$TARGET/release
STRIP=$(ls "$(rustc --print sysroot)"/lib/rustlib/*/bin/llvm-strip 2>/dev/null | head -1 || true)
if [ -n "$STRIP" ]; then "$STRIP" -o "$OUT/codex-riscv64" "$OUT/codex"; else cp "$OUT/codex" "$OUT/codex-riscv64"; fi
ls -la "$OUT/codex-riscv64"
