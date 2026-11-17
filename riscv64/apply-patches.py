#!/usr/bin/env python3
"""Apply the riscv64 changes to a pristine upstream Codex checkout. Idempotent.

Usage: apply-patches.py <codex repo root> <version>
"""
import re
import sys
from pathlib import Path

root = Path(sys.argv[1]) / "codex-rs"
version = sys.argv[2]


def edit(rel, fn):
    p = root / rel
    old = p.read_text()
    new = fn(old)
    if new != old:
        p.write_text(new)
        print(f"patched {rel}")


def must(cond, what):
    if not cond:
        sys.exit(f"apply-patches: upstream changed, cannot {what}")


def workspace(s):
    # V8 has no riscv64 build; code mode runs out of process, so the CLI works without it.
    for member in ("code-mode-host", "code-mode-runtime", "v8-poc"):
        s = re.sub(rf'^\s*"{member}",\n', "", s, flags=re.M)
    s = re.sub(r'^v8 = \{ git = "https://github.com/openai-oss-forks/rusty_v8\.git".*\n', "", s, flags=re.M)
    # The backend offers models by client version; a 0.0.0 build only sees old ones.
    s, n = re.subn(r'(\[workspace\.package\]\nversion = )"[^"]*"', rf'\1"{version}"', s)
    must(n == 1, "set workspace version")
    return s


def cli(s):
    # No target OpenSSL when cross-compiling; build it from source.
    if "openssl-sys = { version" in s:
        return s
    must("[dependencies]\n" in s, "find cli [dependencies]")
    return s.replace("[dependencies]\n", '[dependencies]\nopenssl-sys = { version = "*", features = ["vendored"] }\n', 1)


def seccomp(s):
    if "TargetArch::riscv64" in s:
        return s
    anchor = '        } else if cfg!(target_arch = "aarch64") {\n            TargetArch::aarch64\n'
    must(anchor in s, "add riscv64 seccomp target")
    return s.replace(anchor, anchor + '        } else if cfg!(target_arch = "riscv64") {\n            TargetArch::riscv64\n', 1)


def daemon_target(s):
    if "riscv64gc-unknown-linux-gnu" in s:
        return s
    anchor = '        ("linux", "x86_64") if cfg!(target_env = "gnu") => Ok("x86_64-unknown-linux-gnu"),\n'
    must(anchor in s, "add riscv64 daemon package target")
    return s.replace(anchor, anchor + '        ("linux", "riscv64") => Ok("riscv64gc-unknown-linux-gnu"),\n', 1)


edit("Cargo.toml", workspace)
edit("cli/Cargo.toml", cli)
edit("linux-sandbox/src/seccomp.rs", seccomp)
edit("app-server-daemon/src/prepare_install.rs", daemon_target)
