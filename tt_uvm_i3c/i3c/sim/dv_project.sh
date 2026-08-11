#!/usr/bin/env bash
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
# File        : dv_project.sh
# Description : TT UVM I3C simulation support file.
# Authors     : Duy Huynh, Dang Thai
# Date        : 2026-08-11
#
# *****************************************************************************


DV_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DV_PROJECT_NAME="tt_uvm_i3c"
DV_SIMULATOR="vcs"
DV_TOP="tb_smc_peripherals_top"
DV_FILELIST="sim/generated/compile.f"
DV_TESTPLAN="sim/generated/testplan.dv"
DV_OUT_ROOT="sim/out"
DV_DEFAULT_SCHEDULER="${DV_DEFAULT_SCHEDULER:-auto}"
DV_DEFAULT_DUMP_FORMAT="${DV_DEFAULT_DUMP_FORMAT:-none}"
DV_VIEW_SCHEDULER="${DV_VIEW_SCHEDULER:-auto}"
DV_VIEW_X11="${DV_VIEW_X11:-1}"

DV_HELP_TITLE="TT UVM I3C DV Runner"
DV_HELP_SCOPE="TT I3C"
DV_HELP_EXAMPLE_TEST="smc_i3c_csr_smoke_test"
DV_HELP_SANITY_TEST="smc_i3c_sanity_test"
DV_HELP_TOOL_SETUP="module load vcs/2025.06 verdi/2025.06"
DV_HELP_ENV_COMPONENTS="bundled UVM and an external TT I3C core checkout"
DV_HELP_DEP_ROOT_VAR="I3C_ROOT_DIR"

DUT_MODE="${DUT_MODE:-rtl}"
SOURCE_MODE="${SOURCE_MODE:-pinned}"
I3C_ROOT_DIR="${I3C_ROOT_DIR:-}"
CALIPTRA_ROOT="${CALIPTRA_ROOT:-}"
_DV_EMBEDDED_CALIPTRA_ROOT="${I3C_ROOT_DIR:+$I3C_ROOT_DIR/third_party/caliptra-rtl}"
if [[ -z "$CALIPTRA_ROOT" ]] ||
   [[ ! -f "$CALIPTRA_ROOT/src/caliptra_prim/rtl/caliptra_prim_pkg.sv" &&
      -n "$_DV_EMBEDDED_CALIPTRA_ROOT" &&
      -f "$_DV_EMBEDDED_CALIPTRA_ROOT/src/caliptra_prim/rtl/caliptra_prim_pkg.sv" ]]; then
    [[ -z "$CALIPTRA_ROOT" ]] ||
        echo "[WARNING] Replacing unavailable CALIPTRA_ROOT with the I3C core submodule"
    CALIPTRA_ROOT="$_DV_EMBEDDED_CALIPTRA_ROOT"
fi
unset _DV_EMBEDDED_CALIPTRA_ROOT
I3C_SOURCE_LAYOUT="${I3C_SOURCE_LAYOUT:-auto}"
I3C_SOURCE_PINS="$DV_PROJECT_ROOT/sim/project/i3c_source_pins.mk"
[[ -r "$I3C_SOURCE_PINS" ]] || {
    echo "[ERROR] Missing I3C source pin manifest: $I3C_SOURCE_PINS" >&2
    return 2 2>/dev/null || exit 2
}
_DV_I3C_EXPECTED_BRANCH="${I3C_EXPECTED_BRANCH:-}"
_DV_I3C_EXPECTED_COMMIT="${I3C_EXPECTED_COMMIT:-}"
_DV_CALIPTRA_EXPECTED_COMMIT="${CALIPTRA_EXPECTED_COMMIT:-}"
# shellcheck disable=SC1090
source "$I3C_SOURCE_PINS"
I3C_EXPECTED_BRANCH="${_DV_I3C_EXPECTED_BRANCH:-$I3C_EXPECTED_BRANCH}"
I3C_EXPECTED_COMMIT="${_DV_I3C_EXPECTED_COMMIT:-$I3C_EXPECTED_COMMIT}"
CALIPTRA_EXPECTED_COMMIT="${_DV_CALIPTRA_EXPECTED_COMMIT:-$CALIPTRA_EXPECTED_COMMIT}"
unset _DV_I3C_EXPECTED_BRANCH _DV_I3C_EXPECTED_COMMIT _DV_CALIPTRA_EXPECTED_COMMIT
I3C_MIN_VCS_VERSION="${I3C_MIN_VCS_VERSION:-2020.12}"

DV_UVM_MODE="${DV_UVM_MODE:-external}"
_DV_BUNDLED_UVM_HOME="$DV_PROJECT_ROOT/../third_party/uvm-core-2020.3.1"
DV_UVM_HOME="${DV_UVM_HOME:-${EXT_UVM_HOME:-$_DV_BUNDLED_UVM_HOME}}"
EXT_UVM_HOME="${EXT_UVM_HOME:-$DV_UVM_HOME}"
unset _DV_BUNDLED_UVM_HOME
DV_UVM_USE_DPI="${DV_UVM_USE_DPI:-${EXT_UVM_USE_DPI:-1}}"
DV_FSDB_PLI_DIR="${DV_FSDB_PLI_DIR:-${VERDI_HOME:+$VERDI_HOME/share/PLI/VCS/LINUX64}}"
DV_FSDB_DEFINE="SMC_FSDB_ENABLE"
DV_FSDB_COMPILE_STYLE="integrated"
DV_VCD_DEFINE="SMC_VCD_ENABLE"
DV_VPD_DEFINE="SMC_VPD_ENABLE"
DV_DUMP_RUN_STYLE="generic"
SMC_I3C_COV_STRICT_ILLEGAL="${SMC_I3C_COV_STRICT_ILLEGAL:-0}"
DV_REQUIRED_COVERAGE_METRICS="${DV_REQUIRED_COVERAGE_METRICS:-line,cond,toggle,fsm,branch,group}"

DV_EXTRA_COMPILE_OPTS="-q -lca -timescale=1ns/1ps -error=noIOPCWM +lint=TFIPC-L +vcs+lic+wait +define+UVM_REG_DATA_WIDTH=128"
if [[ "$DUT_MODE" == "rtl" ]]; then
    DV_EXTRA_COMPILE_OPTS+=" +define+SMC_USE_I3C_RTL +define+SMC_USE_I3C_RAL"
fi
if [[ "$SMC_I3C_COV_STRICT_ILLEGAL" == "1" ]]; then
    DV_EXTRA_COMPILE_OPTS+=" +define+SMC_I3C_COV_STRICT_ILLEGAL"
fi

export DUT_MODE SOURCE_MODE I3C_ROOT_DIR CALIPTRA_ROOT
export DV_UVM_HOME EXT_UVM_HOME
export I3C_SOURCE_LAYOUT
export I3C_EXPECTED_BRANCH I3C_EXPECTED_COMMIT CALIPTRA_EXPECTED_COMMIT I3C_MIN_VCS_VERSION
export DV_FSDB_DEFINE DV_FSDB_COMPILE_STYLE DV_VCD_DEFINE DV_VPD_DEFINE DV_DUMP_RUN_STYLE
export DV_REQUIRED_COVERAGE_METRICS
export DV_VIEW_SCHEDULER DV_VIEW_X11

dv_project_preflight() {
    case "$DUT_MODE" in
        rtl|stub) ;;
        *) echo "[ERROR] DUT_MODE must be rtl or stub: $DUT_MODE" >&2; return 2 ;;
    esac
    case "$SMC_I3C_COV_STRICT_ILLEGAL" in
        0|1) ;;
        *) echo "[ERROR] SMC_I3C_COV_STRICT_ILLEGAL must be 0 or 1" >&2; return 2 ;;
    esac

    "$DV_PROJECT_ROOT/sim/vcs_run_script/check_standalone.sh" || return $?

    if [[ "$DV_UVM_MODE" == "external" &&
          ! -f "$DV_UVM_HOME/uvm_pkg.sv" &&
          ! -f "$DV_UVM_HOME/src/uvm_pkg.sv" ]]; then
        echo "[ERROR] UVM package not found under: $DV_UVM_HOME" >&2
        echo "[ERROR] Restore third_party/uvm-core-2020.3.1 or set DV_UVM_HOME." >&2
        return 2
    fi

    if [[ "$DUT_MODE" == "rtl" ]]; then
        if [[ -z "$I3C_ROOT_DIR" ]]; then
            echo "[ERROR] I3C_ROOT_DIR is not set." >&2
            echo "[ERROR] Export I3C_ROOT_DIR=/path/to/tt-i3c-core before running RTL flows." >&2
            return 2
        fi
        "$DV_PROJECT_ROOT/sim/vcs_run_script/check_i3c_source.sh" \
            --root "$I3C_ROOT_DIR" \
            --caliptra-root "$CALIPTRA_ROOT" \
            --layout "$I3C_SOURCE_LAYOUT" \
            --mode "$SOURCE_MODE" \
            --expected-branch "$I3C_EXPECTED_BRANCH" \
            --expected-commit "$I3C_EXPECTED_COMMIT" \
            --expected-caliptra-commit "$CALIPTRA_EXPECTED_COMMIT" || return $?
        MINIMUM="$I3C_MIN_VCS_VERSION" \
            "$DV_PROJECT_ROOT/sim/vcs_run_script/check_vcs_version.sh" || return $?
    else
        echo "[INFO] DUT_MODE=stub: upstream source and version checks skipped"
    fi

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
