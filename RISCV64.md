# Codex CLI for riscv64

This fork builds a native **riscv64** OpenAI Codex CLI. Upstream ships only
x86-64 and aarch64 binaries. The rest of the tree tracks upstream `main`; this
file covers what differs.

Tested on a StarFive VisionFive 2 (JH7110, 4x SiFive U74), Debian, glibc 2.36.
The binary starts in about 40 ms, and `codex sandbox` works: a read-only
filesystem and a seccomp network block, the same as on x86-64 and arm64.

## Build

Cross-compiling is much faster than building on a riscv64 board. A full
release build takes about 18 minutes on an M-series Mac.

```sh
# needs rustup, zig and cargo-zigbuild (cargo install cargo-zigbuild)
./build-riscv64.sh
scp codex-rs/target/riscv64gc-unknown-linux-gnu/release/codex-riscv64 board:/tmp/codex
ssh board sudo install -m 755 /tmp/codex /usr/local/bin/codex
```

Set `GLIBC=2.xx` to target a different minimum glibc. The default is 2.36.

## Changes from upstream

| Change | Why |
|---|---|
| `code-mode-host`, `code-mode-runtime` and `v8-poc` removed from the workspace, along with the `rusty_v8` patch | V8 has no riscv64 build. Code mode runs in a separate host process, so the CLI works without it; only the code-mode feature is unavailable. |
| `linux-sandbox`: `TargetArch::riscv64` added to the seccomp filter | Upstream panicked with `unsupported architecture for seccomp filter`. seccompiler 0.5 already supports riscv64. |
| `cli`: `openssl-sys` built with the `vendored` feature | A cross-compile has no target OpenSSL, so it is built from source. |
| Workspace version set to the matching upstream release, not `0.0.0` | The backend chooses which models to offer by client version. A `0.0.0` build sees only old models. |

When rebasing onto a newer upstream, update the workspace version in
`codex-rs/Cargo.toml` to the matching release tag.
