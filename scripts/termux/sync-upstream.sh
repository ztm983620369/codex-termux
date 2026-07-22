#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

REMOTE=${CODEX_UPSTREAM_REMOTE:-origin}
UPSTREAM_BRANCH=${CODEX_UPSTREAM_BRANCH:-main}
TERMUX_BRANCH=${CODEX_TERMUX_BRANCH:-termux}
DRY_RUN=0
BUILD_ANDROID=0

usage() {
    cat <<'EOF'
Usage: scripts/termux/sync-upstream.sh [--dry-run] [--build-android]

Fetch the official OpenAI main branch and rebase the local Termux patch stack
onto it. The command requires a clean worktree and creates a timestamped backup
branch before changing history.

Environment overrides:
  CODEX_UPSTREAM_REMOTE       Git remote (default: origin)
  CODEX_UPSTREAM_BRANCH       Upstream branch (default: main)
  CODEX_TERMUX_BRANCH         Local patch branch (default: termux)
  CODEX_ALLOW_OTHER_UPSTREAM  Set to 1 to permit a non-openai/codex remote URL
EOF
}

while (($#)); do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --build-android) BUILD_ANDROID=1 ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

cd "$REPO_ROOT"

current_branch=$(git symbolic-ref --quiet --short HEAD) || {
    printf 'Refusing to sync from a detached HEAD.\n' >&2
    exit 1
}
if [[ "$current_branch" != "$TERMUX_BRANCH" ]]; then
    printf 'Switch to %s before syncing (current branch: %s).\n' \
        "$TERMUX_BRANCH" "$current_branch" >&2
    exit 1
fi
if [[ -n $(git status --porcelain) ]]; then
    printf 'Refusing to sync a dirty worktree. Commit or stash changes first.\n' >&2
    exit 1
fi

remote_url=$(git remote get-url "$REMOTE")
case "$remote_url" in
    https://github.com/openai/codex|https://github.com/openai/codex.git|\
    git@github.com:openai/codex.git|ssh://git@github.com/openai/codex|\
    ssh://git@github.com/openai/codex.git)
        ;;
    *)
        if [[ ${CODEX_ALLOW_OTHER_UPSTREAM:-0} != 1 ]]; then
            printf 'Refusing non-official upstream URL: %s\n' "$remote_url" >&2
            printf 'Set CODEX_ALLOW_OTHER_UPSTREAM=1 only for a trusted mirror.\n' >&2
            exit 1
        fi
        ;;
esac

# These settings make repeated conflict resolution deterministic on this clone.
git config rerere.enabled true
git config rerere.autoupdate true
git config rebase.autoStash true
git config merge.conflictStyle zdiff3
git config fetch.prune true

upstream_ref="refs/remotes/$REMOTE/$UPSTREAM_BRANCH"
git fetch --prune "$REMOTE" \
    "+refs/heads/$UPSTREAM_BRANCH:$upstream_ref"

old_head=$(git rev-parse HEAD)
upstream_head=$(git rev-parse "$upstream_ref")
printf 'Termux head:  %s\n' "$old_head"
printf 'Upstream head: %s\n' "$upstream_head"

# Keep the local main branch as a clean mirror, but never overwrite divergent work.
update_local_main() {
    if ! git show-ref --verify --quiet refs/heads/main; then
        return
    fi

    local local_main
    local_main=$(git rev-parse refs/heads/main)
    if git merge-base --is-ancestor "$local_main" "$upstream_head"; then
        git branch --force main "$upstream_ref" >/dev/null
    else
        printf 'Local main diverged; left it unchanged.\n' >&2
    fi
}

if git merge-base --is-ancestor "$upstream_head" "$old_head"; then
    update_local_main
    printf 'The Termux branch already contains the latest upstream commit.\n'
    if ((BUILD_ANDROID)); then
        exec "$SCRIPT_DIR/build-android.sh"
    fi
    exit 0
fi

printf 'Incoming upstream commits: %s\n' \
    "$(git rev-list --count "$old_head..$upstream_head")"
if ((DRY_RUN)); then
    git log --oneline --decorate --first-parent "$old_head..$upstream_head"
    exit 0
fi

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
backup_branch="backup/termux-before-${timestamp}-${old_head:0:10}"
git branch "$backup_branch" "$old_head"
printf 'Safety branch: %s\n' "$backup_branch"

if ! git rebase --rebase-merges "$upstream_ref"; then
    cat >&2 <<EOF

The rebase stopped on a semantic conflict. Resolve the listed files, then run:
  git add <resolved-files>
  git rebase --continue

To return to the exact pre-sync state, run:
  git rebase --abort
The safety branch remains at: $backup_branch
EOF
    exit 1
fi

update_local_main

check_rust_format() {
    local output
    output=$(mktemp "${TMPDIR:-/tmp}/codex-termux-rustfmt.XXXXXX")
    if cargo fmt --all -- --check >"$output" 2>&1; then
        rm -f "$output"
        return 0
    fi

    cat "$output" >&2
    rm -f "$output"
    return 1
}

(
    cd codex-rs
    cargo metadata --locked --no-deps --format-version 1 >/dev/null
    # Stable rustfmt emits one harmless unstable-option warning per crate even
    # when formatting passes. Keep successful upgrades quiet, but preserve the
    # complete diagnostics if the check actually fails.
    check_rust_format
)
git diff --check "$upstream_ref...HEAD"

printf 'Sync complete: %s local commit(s) on top of %s.\n' \
    "$(git rev-list --count "$upstream_ref..HEAD")" "$upstream_ref"
printf 'Rollback branch: %s\n' "$backup_branch"

if ((BUILD_ANDROID)); then
    exec "$SCRIPT_DIR/build-android.sh"
fi
