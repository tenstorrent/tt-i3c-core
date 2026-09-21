#!/usr/bin/env bash

DV_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DV_PROJECT_NAME="tt_uvm_i3c"
DV_SIMULATOR="vcs"
DV_TOP="tb_i3c_top"
DV_FILELIST="sim/generated/compile.f"
DV_TESTPLAN="sim/generated/testplan.dv"
DV_OUT_ROOT="sim/out"
DV_DEFAULT_SCHEDULER="${DV_DEFAULT_SCHEDULER:-auto}"
DV_DEFAULT_DUMP_FORMAT="${DV_DEFAULT_DUMP_FORMAT:-none}"
DV_VIEW_SCHEDULER="${DV_VIEW_SCHEDULER:-auto}"
DV_VIEW_X11="${DV_VIEW_X11:-1}"

DV_HELP_TITLE="TT UVM I3C DV Runner"
DV_HELP_SCOPE="TT I3C"
DV_HELP_EXAMPLE_TEST="i3c_csr_smoke_test"
DV_HELP_SANITY_TEST="i3c_sanity_test"
DV_HELP_TOOL_SETUP="module load vcs/2025.06 verdi/2025.06"
DV_HELP_DEP_ROOT_VAR="I3C_ROOT_DIR"

dv_project_find_native_root() {
    local candidate="$DV_PROJECT_ROOT"
    while [[ "$candidate" != "/" ]]; do
        if [[ -f "$candidate/src/i3c.f" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
        candidate="$(dirname "$candidate")"
    done
    return 1
}

# Native RTL is supplied by the containing repository. Walk upward
# from this package so the default is layout-based rather than tied to a
# revision or path. I3C_ROOT_DIR remains an override for an intentionally separate
# integration workspace.
I3C_ROOT_DIR="${I3C_ROOT_DIR:-}"
if [[ -z "$I3C_ROOT_DIR" ]]; then
    I3C_ROOT_DIR="$(dv_project_find_native_root || true)"
fi
CALIPTRA_ROOT="${CALIPTRA_ROOT:-${I3C_ROOT_DIR:+$I3C_ROOT_DIR/third_party/caliptra-rtl}}"
I3C_MIN_VCS_VERSION="${I3C_MIN_VCS_VERSION:-2020.12}"

DV_UVM_MODE="${DV_UVM_MODE:-external}"
_DV_BUNDLED_UVM_HOME="$DV_PROJECT_ROOT/../third_party/uvm-core-2020.3.1"
DV_UVM_HOME="${DV_UVM_HOME:-${EXT_UVM_HOME:-$_DV_BUNDLED_UVM_HOME}}"
EXT_UVM_HOME="${EXT_UVM_HOME:-$DV_UVM_HOME}"
unset _DV_BUNDLED_UVM_HOME
DV_UVM_USE_DPI="${DV_UVM_USE_DPI:-${EXT_UVM_USE_DPI:-1}}"
DV_FSDB_PLI_DIR="${DV_FSDB_PLI_DIR:-${VERDI_HOME:+$VERDI_HOME/share/PLI/VCS/LINUX64}}"
DV_FSDB_DEFINE="I3C_FSDB_ENABLE"
DV_FSDB_COMPILE_STYLE="integrated"
DV_VCD_DEFINE="I3C_VCD_ENABLE"
DV_VPD_DEFINE="I3C_VPD_ENABLE"
DV_DUMP_RUN_STYLE="generic"
I3C_COV_STRICT_ILLEGAL="${I3C_COV_STRICT_ILLEGAL:-0}"
# IBI closure intentionally disables RTL code coverage.  Treat only the two
# canonical closure columns that remain in the URG report as mandatory.
DV_REQUIRED_COVERAGE_METRICS="${DV_REQUIRED_COVERAGE_METRICS:-assert,group}"

DV_EXTRA_COMPILE_OPTS="-q -lca -timescale=1ns/1ps -error=noIOPCWM +lint=TFIPC-L +vcs+lic+wait +define+UVM_REG_DATA_WIDTH=128"
DV_EXTRA_COMPILE_OPTS+=" +define+I3C_DV_NATIVE_RTL +define+I3C_DV_NATIVE_RAL"
if [[ "$I3C_COV_STRICT_ILLEGAL" == "1" ]]; then
    DV_EXTRA_COMPILE_OPTS+=" +define+I3C_COV_STRICT_ILLEGAL"
fi

export I3C_ROOT_DIR CALIPTRA_ROOT
export DV_UVM_HOME EXT_UVM_HOME
export I3C_MIN_VCS_VERSION
export DV_FSDB_DEFINE DV_FSDB_COMPILE_STYLE DV_VCD_DEFINE DV_VPD_DEFINE DV_DUMP_RUN_STYLE
export DV_REQUIRED_COVERAGE_METRICS
export DV_VIEW_SCHEDULER DV_VIEW_X11

# Keep smoke/RAL tests available to ordinary regressions while limiting the
# coverage command's private testplan snapshot to IBI closure entries.
dv_project_prepare_coverage_testplan() {
    local testplan="$1" tmp="${1}.ibi.tmp"
    awk -F'|' 'BEGIN {OFS="|"}
        /^#/ || NF < 5 { print; next }
        $1 !~ /^i3c_ibi_/ { $5="off" }
        { print }
    ' "$testplan" > "$tmp" && mv "$tmp" "$testplan"
}

dv_project_preflight() {
    case "$I3C_COV_STRICT_ILLEGAL" in
        0|1) ;;
        *) echo "[ERROR] I3C_COV_STRICT_ILLEGAL must be 0 or 1" >&2; return 2 ;;
    esac

    "$DV_PROJECT_ROOT/sim/scripts/check_standalone.sh" || return $?
    "$DV_PROJECT_ROOT/sim/scripts/check_core_vseq_reuse.sh" || return $?

    if [[ "$DV_UVM_MODE" == "external" &&
          ! -f "$DV_UVM_HOME/uvm_pkg.sv" &&
          ! -f "$DV_UVM_HOME/src/uvm_pkg.sv" ]]; then
        echo "[ERROR] UVM package not found under: $DV_UVM_HOME" >&2
        echo "[ERROR] Restore third_party/uvm-core-2020.3.1 or set DV_UVM_HOME." >&2
        return 2
    fi

    if [[ -z "$I3C_ROOT_DIR" || ! -f "$I3C_ROOT_DIR/src/i3c.f" ]]; then
        echo "[ERROR] Native I3C source not found. Set I3C_ROOT_DIR to a checkout containing src/i3c.f." >&2
        return 2
    fi
    if [[ -z "$CALIPTRA_ROOT" ||
          ! -f "$CALIPTRA_ROOT/src/caliptra_prim/rtl/caliptra_prim_pkg.sv" ]]; then
        echo "[ERROR] Caliptra dependency not found. Set CALIPTRA_ROOT to the recursive dependency used by src/i3c.f." >&2
        return 2
    fi
    MINIMUM="$I3C_MIN_VCS_VERSION" \
        "$DV_PROJECT_ROOT/sim/scripts/check_vcs_version.sh" || return $?

    # Generated compile inputs are not versioned. Refresh them after a pull so
    # newly added package dependencies cannot be hidden by a stale filelist.
    "$DV_PROJECT_ROOT/sim/project/generate_dv_inputs.sh" || return $?
}

dv_project_generate() {
    "$DV_PROJECT_ROOT/sim/project/generate_dv_inputs.sh" "$@"
}

dv_project_pre_run() {
    local test_name="$1"
    local waiver_root="$DV_PROJECT_ROOT/verify/tb/sva/waivers"
    local policy_map="$waiver_root/suite_policies.tsv"
    local global_file="$waiver_root/global_waivers.list"
    local policy="functional" pattern selected='' key
    local -a plusargs=()

    if [[ -r "$policy_map" ]]; then
        while read -r pattern selected _; do
            [[ -z "$pattern" || "$pattern" == \#* ]] && continue
            if [[ "$test_name" == "$pattern" ]]; then policy="$selected"; break; fi
            [[ "$test_name" == $pattern ]] && policy="$selected"
        done < "$policy_map"
    fi

    for waiver_file in "$global_file" "$waiver_root/policies/$policy.list"; do
        [[ -r "$waiver_file" ]] || continue
        while IFS= read -r key; do
            key="${key%%#*}"
            key="${key//[[:space:]]/}"
            [[ -n "$key" ]] && plusargs+=("+SVA_WAIVE_$key")
        done < "$waiver_file"
    done

    DV_PROJECT_RUN_PLUSARGS="${plusargs[*]:-}"
    export DV_PROJECT_RUN_PLUSARGS
    printf '[INFO] SVA policy test=%s policy=%s waivers=%s\n' \
        "$test_name" "$policy" "${DV_PROJECT_RUN_PLUSARGS:-(none)}"
}
