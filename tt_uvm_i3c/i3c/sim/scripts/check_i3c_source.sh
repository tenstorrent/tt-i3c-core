#!/bin/bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: check_i3c_source.sh --root <path> --caliptra-root <path>
       --layout auto|embedded|external
       --mode pinned|latest|worktree|snapshot
       --expected-branch <branch>
       --expected-commit <sha>
       --expected-caliptra-commit <sha>

The check is read-only. It never fetches, checks out, or modifies source.
EOF
}

ROOT=""
CALIPTRA_ROOT=""
LAYOUT="auto"
MODE="pinned"
EXPECTED_BRANCH=""
EXPECTED_COMMIT=""
EXPECTED_CALIPTRA_COMMIT=""

git_in_repo() {
    local repo="$1"
    shift
    git -c "safe.directory=$repo" -C "$repo" "$@"
}

canonical_dir() {
    (cd "$1" 2>/dev/null && pwd -P)
}

dirty_summary() {
    local repo="$1"
    local untracked

    if ! git_in_repo "$repo" diff --quiet --ignore-cr-at-eol --ignore-submodules=all --; then
        echo "tracked files differ from HEAD"
    fi
    if ! git_in_repo "$repo" diff --cached --quiet --ignore-cr-at-eol --ignore-submodules=all --; then
        echo "index differs from HEAD"
    fi
    untracked="$(git_in_repo "$repo" ls-files --others --exclude-standard)"
    [[ -z "$untracked" ]] || printf 'untracked: %s\n' "$untracked"
}

print_worktree_mode_commands() {
    echo "[NOTE] To accept this checkout for subsequent development runs:" >&2
    echo "[NOTE]   ./run.sh source mode worktree" >&2
    echo "[NOTE] Verify the saved path, readable HEADs, and selected mode:" >&2
    echo "[NOTE]   ./run.sh source show" >&2
    echo "[NOTE] A saved setup must report Config exists=yes and Source mode=worktree." >&2
    echo "[NOTE] If HEAD differs from the pin, Status=DIFFERS_FROM_PIN_ACCEPTED is expected." >&2
    echo "[NOTE] Validate the complete source/tool preflight before compiling:" >&2
    echo "[NOTE]   ./run.sh doctor" >&2
    echo "[NOTE]   ./run.sh compile --show-output" >&2
    echo "[NOTE] For one compile only, without changing the saved mode:" >&2
    echo "[NOTE]   SOURCE_MODE=worktree ./run.sh compile --show-output" >&2
}

require_clean_repo() {
    local label="$1" repo="$2" dirty
    dirty="$(dirty_summary "$repo")"
    if [[ -n "$dirty" ]]; then
        echo "[ERROR] Pinned $label source is dirty:" >&2
        printf '%s\n' "$dirty" >&2
        echo "[NOTE] Cause: SOURCE_MODE=pinned requires the pinned HEAD and a clean index/worktree." >&2
        echo "[NOTE] Inspect the changes before choosing pinned or worktree mode:" >&2
        printf '[NOTE]   git -C %q status --short\n' "$repo" >&2
        printf '[NOTE]   git -C %q diff --stat\n' "$repo" >&2
        printf '[NOTE]   git -C %q diff --cached --stat\n' "$repo" >&2
        echo "[NOTE] Commit or stash changes for a reproducible pinned run." >&2
        print_worktree_mode_commands
        return 1
    fi
}

require_commit() {
    local label="$1" actual="$2" expected="$3" repo="${4:-}"
    if [[ -z "$expected" || "$actual" != "$expected" ]]; then
        echo "[ERROR] $label commit mismatch" >&2
        echo "[ERROR] Expected: ${expected:-(unset)}" >&2
        echo "[ERROR] Actual  : $actual" >&2
        if [[ -n "$repo" && -n "$expected" ]]; then
            echo "[NOTE] For the reviewed source, run:" >&2
            printf '[NOTE]   git -C %q checkout %q\n' "$repo" "$expected" >&2
        fi
        print_worktree_mode_commands
        return 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --caliptra-root) CALIPTRA_ROOT="$2"; shift 2 ;;
        --layout) LAYOUT="$2"; shift 2 ;;
        --mode) MODE="$2"; shift 2 ;;
        --expected-branch) EXPECTED_BRANCH="$2"; shift 2 ;;
        --expected-commit) EXPECTED_COMMIT="$2"; shift 2 ;;
        --expected-caliptra-commit) EXPECTED_CALIPTRA_COMMIT="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "[ERROR] Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$LAYOUT" in
    auto|embedded|external) ;;
    *) echo "[ERROR] Invalid source layout: $LAYOUT" >&2; exit 2 ;;
esac
case "$MODE" in
    pinned|latest|worktree|snapshot) ;;
    *) echo "[ERROR] Invalid source mode: $MODE" >&2; exit 2 ;;
esac

[[ -n "$ROOT" ]] || { echo "[ERROR] --root is required" >&2; exit 2; }
[[ -n "$CALIPTRA_ROOT" ]] || { echo "[ERROR] --caliptra-root is required" >&2; exit 2; }
if [[ ! -f "$ROOT/src/i3c.f" ]]; then
    echo "[ERROR] Missing I3C filelist: $ROOT/src/i3c.f" >&2
    echo "[NOTE] Set I3C_ROOT_DIR to the tt-i3c-core checkout root." >&2
    echo "[NOTE] Example: export I3C_ROOT_DIR=/path/to/tt-i3c-core" >&2
    exit 1
fi
[[ -f "$ROOT/src/i3c_wrapper.sv" ]] || { echo "[ERROR] Missing I3C top: $ROOT/src/i3c_wrapper.sv" >&2; exit 1; }
[[ -f "$ROOT/src/csr/I3CCSR_uvm.sv" ]] || { echo "[ERROR] Missing I3C RAL package: $ROOT/src/csr/I3CCSR_uvm.sv" >&2; exit 1; }
[[ -f "$ROOT/src/csr/I3CCSR_covergroups.svh" ]] || { echo "[ERROR] Missing I3C RAL coverage include: $ROOT/src/csr/I3CCSR_covergroups.svh" >&2; exit 1; }
[[ -f "$ROOT/src/csr/I3CCSR_sample.svh" ]] || { echo "[ERROR] Missing I3C RAL sampling include: $ROOT/src/csr/I3CCSR_sample.svh" >&2; exit 1; }
[[ -f "$CALIPTRA_ROOT/src/caliptra_prim/rtl/caliptra_prim_pkg.sv" ]] || {
    echo "[ERROR] Missing Caliptra RTL under: $CALIPTRA_ROOT" >&2
    echo "[NOTE] Initialize recursive submodules or set CALIPTRA_ROOT explicitly." >&2
    echo '[NOTE] Embedded example: export CALIPTRA_ROOT="$I3C_ROOT_DIR/third_party/caliptra-rtl"' >&2
    exit 1
}

root_abs="$(canonical_dir "$ROOT")"
caliptra_abs="$(canonical_dir "$CALIPTRA_ROOT")"
embedded_caliptra="$root_abs/third_party/caliptra-rtl"
detected_layout="external"
if [[ -d "$embedded_caliptra" ]] && [[ "$(canonical_dir "$embedded_caliptra")" == "$caliptra_abs" ]]; then
    detected_layout="embedded"
fi
if [[ "$LAYOUT" == "auto" ]]; then
    LAYOUT="$detected_layout"
elif [[ "$LAYOUT" != "$detected_layout" ]]; then
    echo "[ERROR] Requested source layout '$LAYOUT' does not match resolved layout '$detected_layout'" >&2
    echo "[ERROR] I3C root      : $root_abs" >&2
    echo "[ERROR] Caliptra root : $caliptra_abs" >&2
    exit 1
fi

if [[ "$MODE" == "snapshot" ]]; then
    i3c_marker="$root_abs/.ocah_i3c_release_sha"
    caliptra_marker="$caliptra_abs/.ocah_caliptra_release_sha"
    [[ -f "$i3c_marker" ]] || { echo "[ERROR] Missing release SHA marker: $i3c_marker" >&2; exit 1; }
    [[ -f "$caliptra_marker" ]] || { echo "[ERROR] Missing release SHA marker: $caliptra_marker" >&2; exit 1; }
    i3c_commit="$(tr -d '[:space:]' < "$i3c_marker")"
    caliptra_commit="$(tr -d '[:space:]' < "$caliptra_marker")"
    require_commit "I3C snapshot" "$i3c_commit" "$EXPECTED_COMMIT"
    require_commit "Caliptra snapshot" "$caliptra_commit" "$EXPECTED_CALIPTRA_COMMIT"
else
    if ! i3c_commit="$(git_in_repo "$root_abs" rev-parse HEAD 2>&1)"; then
        echo "[ERROR] I3C source is not a readable Git worktree: $root_abs" >&2
        printf '[ERROR] Git: %s\n' "$i3c_commit" >&2
        echo "[NOTE] Use a Git checkout with SOURCE_MODE=worktree." >&2
        echo "[NOTE] For packaged source without Git metadata, use SOURCE_MODE=snapshot." >&2
        exit 1
    fi
    if ! caliptra_commit="$(git_in_repo "$caliptra_abs" rev-parse HEAD 2>&1)"; then
        echo "[ERROR] Caliptra source is not a readable Git worktree: $caliptra_abs" >&2
        printf '[ERROR] Git: %s\n' "$caliptra_commit" >&2
        echo "[NOTE] Initialize the Caliptra submodule or select its Git checkout." >&2
        exit 1
    fi

    if [[ "$MODE" == "pinned" ]]; then
        require_commit "I3C" "$i3c_commit" "$EXPECTED_COMMIT" "$root_abs"
        require_commit "Caliptra" "$caliptra_commit" "$EXPECTED_CALIPTRA_COMMIT" "$caliptra_abs"
        require_clean_repo "I3C" "$root_abs"
        require_clean_repo "Caliptra" "$caliptra_abs"
    elif [[ "$MODE" == "latest" ]]; then
        [[ -n "$EXPECTED_BRANCH" ]] || {
            echo "[ERROR] Expected I3C branch is not configured for SOURCE_MODE=latest" >&2
            echo "[NOTE] Set I3C_EXPECTED_BRANCH in sim/project/i3c_source_pins.mk." >&2
            exit 1
        }
        latest_commit="$(git_in_repo "$root_abs" rev-parse "origin/$EXPECTED_BRANCH" 2>/dev/null || true)"
        [[ -n "$latest_commit" ]] || {
            echo "[ERROR] origin/$EXPECTED_BRANCH is unavailable; run the sync script" >&2
            printf '[NOTE]   git -C %q fetch origin %q\n' "$root_abs" "$EXPECTED_BRANCH" >&2
            print_worktree_mode_commands
            exit 1
        }
        latest_caliptra_commit="$(git_in_repo "$root_abs" rev-parse "$latest_commit:third_party/caliptra-rtl" 2>/dev/null || true)"
        require_commit "I3C latest" "$i3c_commit" "$latest_commit" "$root_abs"
        require_commit "Caliptra for I3C latest" "$caliptra_commit" "$latest_caliptra_commit" "$caliptra_abs"
        require_clean_repo "I3C" "$root_abs"
        require_clean_repo "Caliptra" "$caliptra_abs"
    else
        i3c_dirty="$(dirty_summary "$root_abs")"
        caliptra_dirty="$(dirty_summary "$caliptra_abs")"
        [[ -z "$i3c_dirty" ]] || echo "[WARNING] worktree mode uses dirty I3C source"
        [[ -z "$caliptra_dirty" ]] || echo "[WARNING] worktree mode uses dirty Caliptra source"
    fi
fi

# I3C/Caliptra source provenance (layout/mode/root/commit) echoes suppressed to
# keep startup output compact. Validation above still fails loudly on error;
# the resolved values remain available in $LAYOUT/$MODE/$root_abs/$i3c_commit/
# $caliptra_abs/$caliptra_commit for any caller that needs them.
