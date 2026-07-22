#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
CODEX_RS="$REPO_ROOT/codex-rs"

if (($#)); then
    if (($# == 1)) && [[ "$1" == -h || "$1" == --help ]]; then
        cat <<'EOF'
Usage: scripts/termux/build-android.sh

Build, statically verify, and package the native ARM64 Termux Codex binary.
Configuration is supplied through the environment variables documented in
scripts/termux/README.md.
EOF
        exit 0
    fi
    printf 'This command accepts no positional arguments. Use --help for details.\n' >&2
    exit 2
fi

TARGET=${CODEX_ANDROID_TARGET:-aarch64-linux-android}
ANDROID_API_LEVEL=${ANDROID_API_LEVEL:-24}
BUILD_ROOT=${CODEX_ANDROID_BUILD_ROOT:-${HOME:?}/build/codex2-android}
OUTPUT_ROOT=${CODEX_ANDROID_OUTPUT_ROOT:-${HOME:?}/dist}
CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$CODEX_RS/target/android-arm64}

if [[ "$TARGET" != aarch64-linux-android ]]; then
    printf 'Only aarch64-linux-android is currently packaged by this script.\n' >&2
    exit 1
fi
if [[ $(uname -s) != Linux || $(uname -m) != x86_64 ]]; then
    printf 'This build entry currently requires an x86_64 Linux host.\n' >&2
    exit 1
fi

find_ndk() {
    if [[ -n ${ANDROID_NDK_HOME:-} ]]; then
        printf '%s\n' "$ANDROID_NDK_HOME"
        return
    fi
    if [[ -n ${ANDROID_NDK_ROOT:-} ]]; then
        printf '%s\n' "$ANDROID_NDK_ROOT"
        return
    fi

    local sdk_root=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/opt/android-sdk}}
    local candidate
    if [[ ! -d "$sdk_root/ndk" ]]; then
        return
    fi
    candidate=$(
        find "$sdk_root/ndk" -mindepth 1 -maxdepth 1 -type d -printf '%f\t%p\n' 2>/dev/null \
            | sort -V \
            | tail -n 1 \
            | cut -f2-
    )
    if [[ -n "$candidate" ]]; then
        printf '%s\n' "$candidate"
    fi
}

NDK_ROOT=$(find_ndk)
if [[ -z "$NDK_ROOT" || ! -d "$NDK_ROOT" ]]; then
    printf 'Android NDK not found; set ANDROID_NDK_HOME.\n' >&2
    exit 1
fi

toolchain="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin"
linker="$toolchain/aarch64-linux-android${ANDROID_API_LEVEL}-clang"
cxx="$toolchain/aarch64-linux-android${ANDROID_API_LEVEL}-clang++"
archiver="$toolchain/llvm-ar"
ranlib="$toolchain/llvm-ranlib"
strip="$toolchain/llvm-strip"
for tool in "$linker" "$cxx" "$archiver" "$ranlib" "$strip"; do
    if [[ ! -x "$tool" ]]; then
        printf 'Required Android tool is missing: %s\n' "$tool" >&2
        exit 1
    fi
done

v8_version=$(
    awk '
        $0 == "[[package]]" { in_package = 0 }
        $0 == "name = \"v8\"" { in_package = 1; next }
        in_package && $1 == "version" {
            gsub(/"/, "", $3)
            print $3
            exit
        }
    ' "$CODEX_RS/Cargo.lock"
)
if [[ -z "$v8_version" ]]; then
    printf 'Could not determine the rusty_v8 version from Cargo.lock.\n' >&2
    exit 1
fi

RUSTY_V8_ARCHIVE=${RUSTY_V8_ARCHIVE:-$BUILD_ROOT/librusty_v8-${v8_version}-aarch64-android.a}
if [[ ! -f "$RUSTY_V8_ARCHIVE" ]]; then
    cat >&2 <<EOF
Missing Android rusty_v8 archive:
  $RUSTY_V8_ARCHIVE

Provide the matching archive through RUSTY_V8_ARCHIVE. The archive version must
match v8 $v8_version from codex-rs/Cargo.lock.
EOF
    exit 1
fi
RUSTY_V8_ARCHIVE=$(realpath "$RUSTY_V8_ARCHIVE")

RUSTY_V8_SRC_BINDING_PATH=${RUSTY_V8_SRC_BINDING_PATH:-$BUILD_ROOT/src_binding_release_aarch64-linux-android-v${v8_version}.rs}
if [[ ! -f "$RUSTY_V8_SRC_BINDING_PATH" ]]; then
    cat >&2 <<EOF
Missing Android rusty_v8 Rust binding:
  $RUSTY_V8_SRC_BINDING_PATH

Preserve the generated release binding together with the matching static
archive, or provide it through RUSTY_V8_SRC_BINDING_PATH. Both assets must come
from v8 $v8_version with the same Android release build configuration.
EOF
    exit 1
fi
if (( $(stat -c %s "$RUSTY_V8_SRC_BINDING_PATH") < 10000 )); then
    printf 'rusty_v8 binding is unexpectedly small: %s\n' \
        "$RUSTY_V8_SRC_BINDING_PATH" >&2
    exit 1
fi
RUSTY_V8_SRC_BINDING_PATH=$(realpath "$RUSTY_V8_SRC_BINDING_PATH")

mkdir -p "$BUILD_ROOT" "$OUTPUT_ROOT" "$CARGO_TARGET_DIR"

export ANDROID_NDK_HOME="$NDK_ROOT"
export ANDROID_NDK_ROOT="$NDK_ROOT"
export CARGO_TARGET_DIR
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$linker"
export CC_aarch64_linux_android="$linker"
export CXX_aarch64_linux_android="$cxx"
export AR_aarch64_linux_android="$archiver"
export RANLIB_aarch64_linux_android="$ranlib"
export OPENSSL_STATIC=1
export RUSTY_V8_ARCHIVE
export RUSTY_V8_SRC_BINDING_PATH

page_flag='-C link-arg=-Wl,-z,max-page-size=16384'
export CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS="${CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS:+$CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS }$page_flag"

cd "$CODEX_RS"
if ! rustup target list --installed | grep -Fx "$TARGET" >/dev/null; then
    rustup target add "$TARGET"
fi
cargo metadata --locked --no-deps --format-version 1 >/dev/null

printf 'Building Codex for %s (API %s) with NDK %s and rusty_v8 %s...\n' \
    "$TARGET" "$ANDROID_API_LEVEL" "$(basename "$NDK_ROOT")" "$v8_version"
cargo build --locked --release --target "$TARGET" -p codex-cli --bin codex

source_binary="$CARGO_TARGET_DIR/$TARGET/release/codex"
if [[ ! -x "$source_binary" ]]; then
    printf 'Cargo completed without the expected binary: %s\n' "$source_binary" >&2
    exit 1
fi

full_revision=$(git -C "$REPO_ROOT" rev-parse HEAD)
short_revision=$(git -C "$REPO_ROOT" rev-parse --short=10 HEAD)
upstream_base=$(
    git -C "$REPO_ROOT" merge-base HEAD refs/remotes/origin/main 2>/dev/null \
        || printf unknown
)
if [[ "$upstream_base" == unknown ]]; then
    patch_count=unknown
else
    patch_count=$(git -C "$REPO_ROOT" rev-list --count "$upstream_base..HEAD")
fi
dirty_suffix=
if [[ -n $(git -C "$REPO_ROOT" status --porcelain) ]]; then
    dirty_suffix=-dirty
fi
package_name="codex-termux-aarch64-api${ANDROID_API_LEVEL}-${short_revision}${dirty_suffix}"
package_dir="$OUTPUT_ROOT/$package_name"
archive="$OUTPUT_ROOT/$package_name.tar.gz"
if [[ -e "$package_dir" || -e "$archive" || -e "$archive.sha256" ]]; then
    printf 'Output already exists; move the prior package/archive before rebuilding: %s\n' \
        "$package_name" >&2
    exit 1
fi

mkdir -p "$package_dir"
cp "$source_binary" "$package_dir/codex"
"$strip" "$package_dir/codex"
chmod 0755 "$package_dir/codex"
cp "$SCRIPT_DIR/package/install.sh" "$package_dir/install.sh"
cp "$SCRIPT_DIR/package/README.md" "$package_dir/README.md"
chmod 0755 "$package_dir/install.sh"

"$SCRIPT_DIR/verify-android-binary.sh" "$package_dir/codex"

commit_date=$(git -C "$REPO_ROOT" show -s --format=%cI HEAD)
rust_version=$(rustc --version)
clang_version=$("$linker" --version | sed -n '1p')
binary_size=$(stat -c %s "$package_dir/codex")
cat >"$package_dir/BUILD-INFO.txt" <<EOF
Product: OpenAI Codex CLI with the local Termux compatibility layer
Source repository: https://github.com/openai/codex
Source commit: $full_revision
Source commit date: $commit_date
Source dirty: $([[ -n "$dirty_suffix" ]] && printf yes || printf no)
Official upstream base: $upstream_base
Local patch commits: $patch_count

Rust target: $TARGET
Minimum Android API: $ANDROID_API_LEVEL
Android NDK: $(basename "$NDK_ROOT")
Android Clang: $clang_version
Rust: $rust_version
Cargo profile: release
V8 crate/archive: $v8_version / $RUSTY_V8_ARCHIVE
V8 Rust binding: $RUSTY_V8_SRC_BINDING_PATH
Stripped binary size: $binary_size bytes

Static verification: ARM64 PIE, /system/bin/linker64, 16 KiB LOAD alignment,
and Android system-only dynamic dependencies passed.
EOF
(
    cd "$package_dir"
    sha256sum codex install.sh README.md BUILD-INFO.txt >SHA256SUMS
)
(
    cd "$OUTPUT_ROOT"
    tar -czf "$package_name.tar.gz" "$package_name"
    sha256sum "$package_name.tar.gz" >"$package_name.tar.gz.sha256"
)

printf 'Package: %s\n' "$package_dir"
printf 'Archive: %s.tar.gz\n' "$package_dir"
