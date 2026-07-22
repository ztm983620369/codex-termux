# Termux Codex source snapshot

This repository is a public source snapshot of the local termux branch of
[OpenAI Codex](https://github.com/openai/codex), including the native Android/Termux
compatibility work maintained in this checkout.

Snapshot source commit: 8afa752fda

The upstream Apache 2.0 license and NOTICE are retained. Generated build trees,
local caches, credentials, and device state are intentionally not included.

## Rust build

The Rust workspace lives under codex-rs/. Follow the upstream repository's
tooling instructions from that directory. The Termux-specific helper scripts
are under scripts/termux/.
