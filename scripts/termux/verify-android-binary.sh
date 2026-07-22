#!/usr/bin/env bash
set -euo pipefail

if (($# != 1)); then
    printf 'Usage: %s <codex-android-binary>\n' "$0" >&2
    exit 2
fi

binary=$1
if [[ ! -x "$binary" ]]; then
    printf 'Android binary is missing or not executable: %s\n' "$binary" >&2
    exit 1
fi

file_output=$(file "$binary")
if [[ "$file_output" != *"ELF 64-bit"* || "$file_output" != *"ARM aarch64"* ]]; then
    printf 'Unexpected binary format: %s\n' "$file_output" >&2
    exit 1
fi
if ! readelf -lW "$binary" | grep -F '/system/bin/linker64' >/dev/null; then
    printf 'Binary does not use the Android ARM64 dynamic linker.\n' >&2
    exit 1
fi

bad_alignment=$(readelf -lW "$binary" | awk '$1 == "LOAD" && $NF != "0x4000" { print $NF }')
if [[ -n "$bad_alignment" ]]; then
    printf 'LOAD segments are not all aligned for 16 KiB Android pages: %s\n' \
        "$bad_alignment" >&2
    exit 1
fi

mapfile -t needed < <(
    readelf -dW "$binary" \
        | sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p' \
        | sort -u
)
for library in "${needed[@]}"; do
    case "$library" in
        libc.so|libdl.so|liblog.so|libm.so) ;;
        *)
            printf 'Unexpected dynamic dependency: %s\n' "$library" >&2
            exit 1
            ;;
    esac
done

printf '%s\n' "$file_output"
printf 'Android linker: /system/bin/linker64\n'
printf 'LOAD alignment: 0x4000 (16 KiB)\n'
printf 'Dynamic dependencies: %s\n' "${needed[*]}"
sha256sum "$binary"
