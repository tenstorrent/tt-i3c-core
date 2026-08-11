#!/bin/bash
# *****************************************************************************
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 VNCHIP LABS
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# File        : check_i3c_source.sh
# Description : TT UVM I3C simulation support file.
# Authors     : Duy Huynh, Dang Thai
# Date        : 2026-08-11
#
# *****************************************************************************


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
EXPECTED_BRANCH="tt/main"
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
    local index
    local -a untracked=()

    if ! git_in_repo "$repo" diff --quiet --ignore-cr-at-eol --ignore-submodules=all --; then
        echo "tracked files differ from HEAD"
    fi
    if ! git_in_repo "$repo" diff --cached --quiet --ignore-cr-at-eol --ignore-submodules=all --; then
        echo "index differs from HEAD"
    fi
    mapfile -t untracked < <(
        git_in_repo "$repo" ls-files --others --exclude-standard 2>/dev/null |
            head -n 11
    )
    for ((index = 0; index < ${#untracked[@]} && index < 10; index++)); do
        printf 'untracked: %s\n' "${untracked[$index]}"
    done
    if ((${#untracked[@]} > 10)); then
        echo "additional untracked paths omitted"
    fi
}

warn_dirty_repo() {
    local label="$1" repo="$2" dirty
    dirty="$(dirty_summary "$repo")"
    if [[ -n "$dirty" ]]; then
        echo "[WARNING] $label source has local changes; results are not reproducible from the recorded commit alone:" >&2
        printf '%s\n' "$dirty" >&2
    fi
}

warn_commit_mismatch() {
    local label="$1" actual="$2" expected="$3"
    if [[ -z "$expected" || "$actual" != "$expected" ]]; then
        echo "[WARNING] $label commit mismatch" >&2
        echo "[WARNING] Expected: ${expected:-(unset)}" >&2
        echo "[WARNING] Actual  : ${actual:-(unavailable)}" >&2
        echo "[WARNING] Source files will still be accepted; record the actual revision with the test results." >&2
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
    echo "[ERROR] Check I3C_ROOT_DIR or initialize the selected I3C checkout." >&2
    exit 1
fi
[[ -f "$ROOT/src/i3c_wrapper.sv" ]] || { echo "[ERROR] Missing I3C top: $ROOT/src/i3c_wrapper.sv" >&2; exit 1; }
[[ -f "$ROOT/src/csr/I3CCSR_uvm.sv" ]] || { echo "[ERROR] Missing I3C RAL package: $ROOT/src/csr/I3CCSR_uvm.sv" >&2; exit 1; }
[[ -f "$ROOT/src/csr/I3CCSR_covergroups.svh" ]] || { echo "[ERROR] Missing I3C RAL coverage include: $ROOT/src/csr/I3CCSR_covergroups.svh" >&2; exit 1; }
[[ -f "$ROOT/src/csr/I3CCSR_sample.svh" ]] || { echo "[ERROR] Missing I3C RAL sampling include: $ROOT/src/csr/I3CCSR_sample.svh" >&2; exit 1; }
[[ -f "$CALIPTRA_ROOT/src/caliptra_prim/rtl/caliptra_prim_pkg.sv" ]] || {
    echo "[ERROR] Missing Caliptra RTL under: $CALIPTRA_ROOT" >&2
    echo "[ERROR] Check CALIPTRA_ROOT or initialize the selected Caliptra checkout." >&2
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
    i3c_commit=""
    caliptra_commit=""
    if [[ -f "$i3c_marker" ]]; then
        i3c_commit="$(tr -d '[:space:]' < "$i3c_marker")"
    else
        echo "[WARNING] I3C snapshot has no release SHA marker: $i3c_marker" >&2
    fi
    if [[ -f "$caliptra_marker" ]]; then
        caliptra_commit="$(tr -d '[:space:]' < "$caliptra_marker")"
    else
        echo "[WARNING] Caliptra snapshot has no release SHA marker: $caliptra_marker" >&2
    fi
    warn_commit_mismatch "I3C snapshot" "$i3c_commit" "$EXPECTED_COMMIT"
    warn_commit_mismatch "Caliptra snapshot" "$caliptra_commit" "$EXPECTED_CALIPTRA_COMMIT"
else
    i3c_git_available=1
    caliptra_git_available=1
    if ! i3c_commit="$(git_in_repo "$root_abs" rev-parse HEAD 2>/dev/null)"; then
        i3c_commit=""
        i3c_git_available=0
        echo "[WARNING] I3C source is a plain directory or unreadable Git worktree: $root_abs" >&2
        echo "[WARNING] Commit provenance cannot be checked; source files will still be accepted." >&2
    fi
    if ! caliptra_commit="$(git_in_repo "$caliptra_abs" rev-parse HEAD 2>/dev/null)"; then
        caliptra_commit=""
        caliptra_git_available=0
        echo "[WARNING] Caliptra source is a plain directory or unreadable Git worktree: $caliptra_abs" >&2
        echo "[WARNING] Commit provenance cannot be checked; source files will still be accepted." >&2
    fi

    if [[ "$MODE" == "pinned" ]]; then
        if (( i3c_git_available )); then
            warn_commit_mismatch "I3C" "$i3c_commit" "$EXPECTED_COMMIT"
            warn_dirty_repo "I3C" "$root_abs"
        fi
        if (( caliptra_git_available )); then
            warn_commit_mismatch "Caliptra" "$caliptra_commit" "$EXPECTED_CALIPTRA_COMMIT"
            warn_dirty_repo "Caliptra" "$caliptra_abs"
        fi
    elif [[ "$MODE" == "latest" ]]; then
        latest_commit=""
        latest_caliptra_commit=""
        if (( i3c_git_available )); then
            latest_commit="$(git_in_repo "$root_abs" rev-parse "origin/$EXPECTED_BRANCH" 2>/dev/null || true)"
            if [[ -n "$latest_commit" ]]; then
                latest_caliptra_commit="$(git_in_repo "$root_abs" rev-parse "$latest_commit:third_party/caliptra-rtl" 2>/dev/null || true)"
                warn_commit_mismatch "I3C latest" "$i3c_commit" "$latest_commit"
            else
                echo "[WARNING] origin/$EXPECTED_BRANCH is unavailable; latest revision cannot be verified." >&2
            fi
            warn_dirty_repo "I3C" "$root_abs"
        fi
        if (( caliptra_git_available )); then
            if [[ -n "$latest_caliptra_commit" ]]; then
                warn_commit_mismatch "Caliptra for I3C latest" "$caliptra_commit" "$latest_caliptra_commit"
            else
                echo "[WARNING] Caliptra revision for origin/$EXPECTED_BRANCH cannot be verified." >&2
            fi
            warn_dirty_repo "Caliptra" "$caliptra_abs"
        fi
    else
        (( ! i3c_git_available )) || warn_dirty_repo "I3C worktree" "$root_abs"
        (( ! caliptra_git_available )) || warn_dirty_repo "Caliptra worktree" "$caliptra_abs"
    fi
fi

# I3C/Caliptra source provenance (layout/mode/root/commit) echoes suppressed to
# keep startup output compact. Missing required source files still fail; Git
# provenance differences only warn. Resolved values remain available in
# $LAYOUT/$MODE/$root_abs/$i3c_commit/$caliptra_abs/$caliptra_commit.
