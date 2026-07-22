# Termux maintenance layer

This clone keeps official source and Android changes on separate branches:

- `main` is a clean mirror of `origin/main`.
- `termux` contains the small local patch stack on top of that mirror.
- `backup/termux-*` branches are immutable recovery points created before an
  upstream rebase.

## Upgrade to current OpenAI source

Start from a clean `termux` worktree:

```sh
git switch termux
scripts/termux/sync-upstream.sh --dry-run
scripts/termux/sync-upstream.sh
```

The sync command verifies the official remote URL, fetches only `main`, creates
a safety branch, rebases the Termux commits, updates the clean local `main`, and
checks Cargo metadata plus formatting. Git `rerere` is enabled locally so an
identical conflict resolution is reused on later upgrades.

If a real semantic conflict remains, resolve it and run `git rebase --continue`.
Use `git rebase --abort` to return to the pre-sync state; the printed safety
branch is an additional recovery point.

## Build the native ARM64 package

The build needs an Android NDK, the pinned Rust toolchain/Android target, and a
matching Android rusty_v8 archive. Defaults match this host:

```text
NDK: newest directory below /opt/android-sdk/ndk
API: 24
rusty_v8: ~/build/codex2-android/librusty_v8-<version>-aarch64-android.a
binding: ~/build/codex2-android/src_binding_release_aarch64-linux-android-v<version>.rs
output: ~/dist/codex-termux-aarch64-api24-<commit>/
```

Run:

```sh
scripts/termux/build-android.sh
```

Useful overrides are `ANDROID_NDK_HOME`, `ANDROID_API_LEVEL`,
`RUSTY_V8_ARCHIVE`, `RUSTY_V8_SRC_BINDING_PATH`, `CODEX_ANDROID_BUILD_ROOT`,
`CODEX_ANDROID_OUTPUT_ROOT`, and `CARGO_TARGET_DIR`. The build is locked to
`Cargo.lock`, strips the binary, verifies ARM64 Android linkage and 16 KiB LOAD
alignment, then emits a package, checksums, provenance, and a `.tar.gz` archive.

To sync and immediately build in one guarded operation:

```sh
scripts/termux/sync-upstream.sh --build-android
```
