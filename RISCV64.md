# Codex CLI for riscv64

Native **riscv64** builds of the OpenAI Codex CLI. Upstream ships only x86-64
and aarch64.

A GitHub Action checks daily for a new upstream stable release. When one
appears, it applies this repo's patches, cross-compiles for riscv64, and
publishes the result under [Releases](../../releases). The rest of this tree is
an upstream snapshot; only `riscv64/` and the release workflow are maintained
here.

Tested on a StarFive VisionFive 2 (JH7110, 4x SiFive U74), Debian, glibc 2.36:

- The binary starts in about 40 ms.
- `codex sandbox` works: read-only filesystem and seccomp network block.
- The background app-server daemon works.
- Code mode works through OpenAI's own aarch64 `codex-code-mode-host` (V8), run
  under qemu-user. The installer handles the setup.

## Install and update

```sh
sudo apt install ripgrep bubblewrap
curl -fsSL https://raw.githubusercontent.com/temidaradev/codex-riscv64/main/riscv64/install.sh | sudo sh
codex-update          # later: fetch the newest release
codex-update 0.169.0  # or a specific one
```

The installer places the official package layout in `/opt/codex`:

- `bin/`;
- `codex-package.json`;
- `codex-path/rg` and `codex-resources/bwrap`, taken from the system packages;
- a link at `/usr/local/bin/codex`.

The app-server daemon requires that layout.

The installer also sets up code mode. It downloads the version-matched official
aarch64 code-mode host from npm and verifies its integrity hash. If qemu isn't
already registered, it installs a static qemu-aarch64 10.x from Debian trixie
and registers it with binfmt_misc. The host is installed behind a wrapper that
pins `QEMU_CPU=neoverse-n1`, because qemu's default `max` CPU emulates
pointer authentication and is very slow. Code mode is still an
under-development feature upstream; enable it in `~/.codex/config.toml`:

```toml
[features]
code_mode = true
```

## Build it yourself

```sh
# needs rustup, zig and cargo-zigbuild
riscv64/package.sh <path to an openai/codex checkout> <version> dist/
sudo riscv64/install.sh dist/codex-<version>-riscv64gc-unknown-linux-gnu.tar.gz   # on the device
```

Set `GLIBC=2.xx` to target a different minimum glibc. The default is 2.36.

## Patches (`riscv64/apply-patches.py`)

| Change | Why |
|---|---|
| `code-mode-host`, `code-mode-runtime` and `v8-poc` removed from the workspace, along with the `rusty_v8` patch | V8 has no riscv64 build. Code mode runs in a separate host process; `install.sh` supplies the official aarch64 host under qemu, and the package ships a stub as a fallback. |
| `linux-sandbox`: `TargetArch::riscv64` added to the seccomp filter | Upstream panicked with `unsupported architecture for seccomp filter`. |
| `app-server-daemon`: riscv64 package target added | Without it the daemon refuses to install from the package. |
| `cli`: `openssl-sys` built with the `vendored` feature | A cross-compile has no target OpenSSL. |
| Workspace version set to the upstream version | The backend offers models by client version; a `0.0.0` build sees only old ones. |

The script fails loudly if upstream code moves, rather than producing a broken
build.
