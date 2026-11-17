#!/bin/sh
# Install or update Codex on a riscv64 Linux machine from the codex-riscv64 GitHub releases.
# Usage: install.sh [version|path/to/package.tar.gz]   (default: latest release)
# Installed as /usr/local/bin/codex-update.
set -eu
REPO=${CODEX_RISCV64_REPO:-temidaradev/codex-riscv64}
TARGET=riscv64gc-unknown-linux-gnu
ROOT=/opt/codex
[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
for dep in rg bwrap; do
  command -v $dep >/dev/null || { echo "missing $dep: apt install ripgrep bubblewrap" >&2; exit 1; }
done
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

ARG=${1:-latest}
if [ -f "$ARG" ]; then
  cp "$ARG" "$T/pkg.tar.gz"
else
  if [ "$ARG" = latest ]; then
    TAG=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')
  else
    TAG=v${ARG#v}
  fi
  NAME=codex-${TAG#v}-$TARGET.tar.gz
  URL=https://github.com/$REPO/releases/download/$TAG/$NAME
  curl -fsSL "$URL" -o "$T/pkg.tar.gz"
  curl -fsSL "$URL.sha256" | awk '{print $1"  '"$T"'/pkg.tar.gz"}' | sha256sum -c - >/dev/null
fi

tar -xzf "$T/pkg.tar.gz" -C "$T"
PKG=$(find "$T" -mindepth 1 -maxdepth 1 -type d -name 'codex-*' | head -1)
VERSION=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$PKG/codex-package.json")
# rg and bwrap must be riscv64 builds, so they come from this system's packages.
install -m 755 "$(command -v rg)" "$PKG/codex-path/rg"
install -m 755 "$(command -v bwrap)" "$PKG/codex-resources/bwrap"

DEST=$ROOT/releases/$VERSION
mkdir -p "$ROOT/releases"
rm -rf "$DEST.new" && mv "$PKG" "$DEST.new" && rm -rf "$DEST" && mv "$DEST.new" "$DEST"
ln -sfn "releases/$VERSION" "$ROOT/current.new" && mv -T "$ROOT/current.new" "$ROOT/current"
ln -sfn "$ROOT/current/bin/codex" /usr/local/bin/codex
curl -fsSL "https://raw.githubusercontent.com/$REPO/main/riscv64/install.sh" -o /usr/local/bin/codex-update.new \
  && chmod 755 /usr/local/bin/codex-update.new && mv /usr/local/bin/codex-update.new /usr/local/bin/codex-update
# Keep the two newest releases.
ls -1dt "$ROOT"/releases/*/ | tail -n +3 | xargs -r rm -rf
/usr/local/bin/codex --version
