#!/system/bin/sh
set -eu

umask 022

package_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_binary="$package_dir/codex"

if [ -z "${PREFIX:-}" ]; then
    printf '%s\n' 'PREFIX is not set. Run this installer inside Termux.' >&2
    exit 1
fi

case "$(uname -m)" in
    aarch64|arm64) ;;
    *)
        printf 'Unsupported architecture: %s (expected aarch64)\n' "$(uname -m)" >&2
        exit 1
        ;;
esac

if [ ! -x "$source_binary" ]; then
    printf 'Missing executable: %s\n' "$source_binary" >&2
    exit 1
fi

mkdir -p "$PREFIX/bin"
timestamp=$(date +%Y%m%d-%H%M%S)
tmp_codex="$PREFIX/bin/.codex.termux.$$"
tmp_host="$PREFIX/bin/.codex-code-mode-host.termux.$$"
trap 'rm -f "$tmp_codex" "$tmp_host"' EXIT HUP INT TERM

cp "$source_binary" "$tmp_codex"
chmod 0755 "$tmp_codex"
ln -s codex "$tmp_host"

backup_path() {
    path=$1
    if [ ! -e "$path" ] && [ ! -L "$path" ]; then
        return
    fi

    backup="$path.backup-$timestamp"
    suffix=1
    while [ -e "$backup" ] || [ -L "$backup" ]; do
        backup="$path.backup-$timestamp-$suffix"
        suffix=$((suffix + 1))
    done
    mv "$path" "$backup"
    printf 'Backed up %s to %s\n' "$path" "$backup"
}

backup_path "$PREFIX/bin/codex"
mv "$tmp_codex" "$PREFIX/bin/codex"
backup_path "$PREFIX/bin/codex-code-mode-host"
mv "$tmp_host" "$PREFIX/bin/codex-code-mode-host"

trap - EXIT HUP INT TERM
home=${HOME:-"$PREFIX/../home"}
codex_home=${CODEX_HOME:-"$home/.codex"}

printf 'Installed %s\n' "$PREFIX/bin/codex"
printf 'Code-mode host: %s -> codex\n' "$PREFIX/bin/codex-code-mode-host"
printf 'Codex home: %s\n' "$codex_home"
printf '%s\n' 'Run: hash -r; codex --version; codex doctor'
