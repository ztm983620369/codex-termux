# Codex CLI for Termux (Android ARM64)

This package contains a native `aarch64-linux-android` Codex binary built from
OpenAI's current source plus the local Termux compatibility layer. It does not
require glibc, proot, or a Linux compatibility distribution.

Install it from an ARM64 Termux session:

```sh
./install.sh
hash -r
codex --version
codex doctor
```

The installer places `codex` in `$PREFIX/bin` and creates
`codex-code-mode-host -> codex` for the isolated V8/code-mode process. Existing
files are timestamped and preserved before replacement. It does not modify
`CODEX_HOME` or shell startup files, so the normal `$HOME/.codex` data remains
in place.

Termux-specific behavior includes CA/shell/temp-directory discovery, vendored
TLS, file-backed credential storage, `termux-clipboard-set` integration when
available, Android-compatible file locking, and native tab/session identity
notifications. The standalone Linux updater is intentionally disabled; install
a newly built package to upgrade.

See `BUILD-INFO.txt` and `SHA256SUMS` for exact source and binary provenance.
