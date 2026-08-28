#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$SCRIPT_DIR/check_i3c_source.sh"
BASE_ROOT="${1:-${TMPDIR:-/tmp}}"
TEST_ROOT="$BASE_ROOT/ocah_i3c_source_self_test.$$"
I3C_REPO="$TEST_ROOT/i3c-core"
CALIPTRA_REPO="$TEST_ROOT/caliptra-rtl"

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

expect_failure() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "[ERROR] Expected failure: $label" >&2
        return 1
    fi
}

init_repo() {
    local repo="$1"
    git -C "$repo" init -q
    git -C "$repo" config user.name "OCAH source self-test"
    git -C "$repo" config user.email "ocah-source-self-test@invalid"
}

rm -rf "$TEST_ROOT"
mkdir -p "$I3C_REPO/src/csr" "$CALIPTRA_REPO/src/caliptra_prim/rtl"

printf '// self-test\n' > "$I3C_REPO/src/i3c_wrapper.sv"
printf '%s\n' 'src/i3c_wrapper.sv' > "$I3C_REPO/src/i3c.f"
printf '// self-test\n' > "$I3C_REPO/src/csr/I3CCSR_uvm.sv"
printf '// self-test\n' > "$I3C_REPO/src/csr/I3CCSR_covergroups.svh"
printf '// self-test\n' > "$I3C_REPO/src/csr/I3CCSR_sample.svh"
printf '// self-test\n' > "$CALIPTRA_REPO/src/caliptra_prim/rtl/caliptra_prim_pkg.sv"

init_repo "$I3C_REPO"
init_repo "$CALIPTRA_REPO"
git -C "$CALIPTRA_REPO" add src
git -C "$CALIPTRA_REPO" commit -q -m "self-test Caliptra source"

caliptra_commit="$(git -C "$CALIPTRA_REPO" rev-parse HEAD)"
git -C "$I3C_REPO" add src
git -C "$I3C_REPO" update-index --add \
    --cacheinfo "160000,$caliptra_commit,third_party/caliptra-rtl"
git -C "$I3C_REPO" commit -q -m "self-test I3C source"
i3c_commit="$(git -C "$I3C_REPO" rev-parse HEAD)"
common_args=(
    --root "$I3C_REPO"
    --caliptra-root "$CALIPTRA_REPO"
    --layout external
    --mode pinned
    --expected-branch tt/main
    --expected-commit "$i3c_commit"
    --expected-caliptra-commit "$caliptra_commit"
)

"$CHECKER" "${common_args[@]}" >/dev/null

expect_failure "wrong Caliptra pin" \
    "$CHECKER" "${common_args[@]:0:12}" \
    --expected-caliptra-commit 0000000000000000000000000000000000000000

printf '// dirty\n' >> "$I3C_REPO/src/i3c_wrapper.sv"
expect_failure "dirty I3C source" "$CHECKER" "${common_args[@]}"
git -C "$I3C_REPO" checkout -q -- src/i3c_wrapper.sv

expect_failure "layout mismatch" \
    "$CHECKER" "${common_args[@]:0:4}" --layout embedded "${common_args[@]:6}"

echo "[PASS] I3C external source-layout checks"
