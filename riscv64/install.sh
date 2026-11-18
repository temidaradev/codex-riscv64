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

tar --no-same-owner -xzf "$T/pkg.tar.gz" -C "$T"
PKG=$(find "$T" -mindepth 1 -maxdepth 1 -type d -name 'codex-*' | head -1)
VERSION=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$PKG/codex-package.json")
# rg and bwrap must be riscv64 builds, so they come from this system's packages.
install -m 755 "$(command -v rg)" "$PKG/codex-path/rg"
install -m 755 "$(command -v bwrap)" "$PKG/codex-resources/bwrap"

# Code mode needs V8, which has no riscv64 build. Use OpenAI's static aarch64
# code-mode host of the same version, run through qemu-user + binfmt_misc.
setup_qemu() {
  [ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] && return 0
  MIRROR=${DEBIAN_MIRROR:-https://deb.debian.org/debian}
  Q=$(curl -fsSL "$MIRROR/pool/main/q/qemu/" | grep -oE 'qemu-user_10\.0\.[0-9]+\+ds-0\+deb13u[0-9]+_riscv64\.deb' | sort -uV | tail -1)
  [ -n "$Q" ] || return 1
  mkdir -p "$T/q" && curl -fsSL "$MIRROR/pool/main/q/qemu/$Q" -o "$T/q/q.deb"
  (cd "$T/q" && ar x q.deb && tar -xf data.tar.* ./usr/bin/qemu-aarch64)
  install -m 755 "$T/q/usr/bin/qemu-aarch64" /usr/local/lib/qemu-aarch64
  printf '%s\n' ':qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/local/lib/qemu-aarch64:POCF' > /etc/binfmt.d/qemu-aarch64.conf
  systemctl restart systemd-binfmt
}
install_code_mode_host() {
  META=$(curl -fsSL "https://registry.npmjs.org/@openai/codex/$VERSION-linux-arm64") || return 1
  set -- $(printf '%s' "$META" | python3 -c 'import json,sys; d=json.load(sys.stdin)["dist"]; print(d["tarball"], d["integrity"])')
  curl -fsSL "$1" -o "$T/arm64.tgz"
  [ "sha512-$(openssl dgst -sha512 -binary "$T/arm64.tgz" | base64 -w0)" = "$2" ] || { echo "arm64 package integrity mismatch" >&2; return 1; }
  tar -xzf "$T/arm64.tgz" -C "$T" package/vendor/aarch64-unknown-linux-musl/bin/codex-code-mode-host
  install -m 755 "$T/package/vendor/aarch64-unknown-linux-musl/bin/codex-code-mode-host" "$PKG/bin/codex-code-mode-host.aarch64"
  cat > "$PKG/bin/codex-code-mode-host" <<'WRAP'
#!/bin/sh
# OpenAI's aarch64 code-mode host (V8) via qemu-user; neoverse-n1 avoids qemu's slow pointer-auth emulation.
QEMU_CPU=${QEMU_CPU:-neoverse-n1} exec "$(dirname "$0")/codex-code-mode-host.aarch64" "$@"
WRAP
  chmod 755 "$PKG/bin/codex-code-mode-host"
}
if setup_qemu && install_code_mode_host; then
  echo "code mode: aarch64 host via qemu-user"
else
  echo "code mode: unavailable (kept stub host)" >&2
fi

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
