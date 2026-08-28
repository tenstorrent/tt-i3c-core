#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PACKAGE_ROOT="$(cd "$PROJECT_ROOT/.." && pwd)"

failures=0

require_file() {
    local path="$1"
    if [[ ! -r "$path" ]]; then
        printf '[ERROR] Missing standalone dependency: %s\n' "$path" >&2
        failures=1
    fi
}

require_file "$PACKAGE_ROOT/LICENSE"
require_file "$PACKAGE_ROOT/NOTICE"
require_file "$PACKAGE_ROOT/run.sh"
require_file "$PROJECT_ROOT/verify/vip/axi4lite_vip/axi4lite_vip_pkg.sv"
require_file "$PROJECT_ROOT/verify/vip/i3c_vip/i3c_vip_pkg.sv"
require_file "$PROJECT_ROOT/rtl/wrappers/smc_i3c_axi_adapter.sv"
require_file "$PROJECT_ROOT/rtl/wrappers/smc_i3c_wrapper.sv"

forbidden_pattern='/VNCHIP/|/home/[A-Za-z0-9_.-]+/|git\.vnchip|smc_shared|OCAH_DEPS_ROOT|ocah_local_env|env[[:space:]]+ocah'
runtime_files=()
while IFS= read -r -d '' runtime_file; do
    runtime_files+=("$runtime_file")
done < <(
    find "$PROJECT_ROOT" \
        \( -path "$PROJECT_ROOT/sim/generated" -o -path "$PROJECT_ROOT/sim/out" \) -prune -o \
        -type f \
        \( -name '*.sh' -o -name '*.bash' -o -name '*.mk' -o \
           -name '*.f' -o -name 'Makefile' \) \
        ! -path "$PROJECT_ROOT/sim/project/i3c_source.local.mk" \
        ! -name 'check_standalone.sh' -print0
)
if ((${#runtime_files[@]} > 0)) &&
   grep -En "$forbidden_pattern" "${runtime_files[@]}" >/dev/null 2>&1; then
    printf '[ERROR] Host- or OCAH-specific runtime path remains in the standalone package\n' >&2
    grep -En "$forbidden_pattern" "${runtime_files[@]}" >&2 || true
    failures=1
fi
if ((${#runtime_files[@]} > 0)) &&
   grep -Fn "$PACKAGE_ROOT" "${runtime_files[@]}" >/dev/null 2>&1; then
    printf '[ERROR] Current host path remains in the standalone package\n' >&2
    grep -Fn "$PACKAGE_ROOT" "${runtime_files[@]}" >&2 || true
    failures=1
fi

while IFS= read -r link; do
    resolved="$(readlink -f "$link" 2>/dev/null || true)"
    case "$resolved" in
        "$PACKAGE_ROOT"/*) ;;
        *)
            printf '[ERROR] Symlink escapes standalone package: %s -> %s\n' "$link" "$resolved" >&2
            failures=1
            ;;
    esac
done < <(find "$PACKAGE_ROOT" -type l -print)

if ((failures == 0)); then
    printf '[INFO] Standalone package boundary checks passed\n'
fi
exit "$failures"
