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
# File        : project_config.sh
# Description : TT UVM I3C simulation support file.
# Authors     : Duy Huynh, Dang Thai
# Date        : 2026-08-11
#
# *****************************************************************************


runner_project_find_config() {
    local candidate
    if [[ -n "${DV_PROJECT_CONFIG:-}" ]]; then
        printf '%s\n' "$DV_PROJECT_CONFIG"
        return
    fi
    for candidate in "$RUNNER_ROOT/dv_project.sh" "$RUNNER_ROOT/sim/dv_project.sh"; do
        [[ -r "$candidate" ]] && { printf '%s\n' "$candidate"; return; }
    done
}

runner_project_abs_path() {
    local value="$1"
    [[ -z "$value" || "$value" == /* ]] && { printf '%s\n' "$value"; return; }
    printf '%s/%s\n' "${DV_PROJECT_ROOT:-$RUNNER_ROOT}" "$value"
}

runner_project_load() {
    local config
    config="$(runner_project_find_config)"
    export DV_PROJECT_ROOT="${DV_PROJECT_ROOT:-$RUNNER_ROOT}"
    export RUNNER_PROJECT_CONFIG=''

    if [[ -n "$config" ]]; then
        [[ "$config" == /* ]] || config="$RUNNER_ROOT/$config"
        [[ -r "$config" ]] || { echo "[ERROR] Project configuration is not readable: $config" >&2; return 2; }
        # Project configuration is trusted code and may define lifecycle hooks.
        # shellcheck source=/dev/null
        source "$config"
        export RUNNER_PROJECT_CONFIG="$config"
    fi

    export DV_PROJECT_NAME="${DV_PROJECT_NAME:-unconfigured}"
    export DV_SIMULATOR="${DV_SIMULATOR:-vcs}"
    export DV_TOP="${DV_TOP:-${TOP:-tb_top}}"
    export DV_FILELIST="${DV_FILELIST:-${FILELIST:-filelist.f}}"
    export DV_TESTPLAN="${DV_TESTPLAN:-${TEST_LIST_FILE:-testplan.dv}}"
    export DV_OUT_ROOT="${DV_OUT_ROOT:-${OUT_DIR:-$DV_PROJECT_ROOT/out}}"
    export DV_UVM_MODE="${DV_UVM_MODE:-${UVM_MODE:-builtin}}"
    export DV_UVM_HOME="${DV_UVM_HOME:-${UVM_HOME:-}}"
    export DV_UVM_USE_DPI="${DV_UVM_USE_DPI:-${UVM_USE_DPI:-1}}"
    export DV_EXTRA_COMPILE_OPTS="${DV_EXTRA_COMPILE_OPTS:-${EXTRA_COMPILE_OPTS:-}}"
    export DV_EXTRA_RUN_OPTS="${DV_EXTRA_RUN_OPTS:-${EXTRA_RUN_OPTS:-}}"
    export DV_FSDB_PLI_DIR="${DV_FSDB_PLI_DIR:-}"
    export DV_FSDB_DEFINE="${DV_FSDB_DEFINE:-DV_FSDB_ENABLE}"
    export DV_FSDB_COMPILE_STYLE="${DV_FSDB_COMPILE_STYLE:-integrated}"
    export DV_VCD_DEFINE="${DV_VCD_DEFINE:-DV_VCD_ENABLE}"
    export DV_VPD_DEFINE="${DV_VPD_DEFINE:-DV_VPD_ENABLE}"
    export DV_DUMP_RUN_STYLE="${DV_DUMP_RUN_STYLE:-generic}"
    export DV_DEFAULT_SCHEDULER="${DV_DEFAULT_SCHEDULER:-auto}"
    export DV_DEFAULT_COMPILE_JOBS="${DV_DEFAULT_COMPILE_JOBS:-4}"
    export DV_DEFAULT_DUMP_FORMAT="${DV_DEFAULT_DUMP_FORMAT:-none}"
    export DV_VERDI_SOURCE_MODE="${DV_VERDI_SOURCE_MODE:-auto}"
    export DV_VERDI_TOP="${DV_VERDI_TOP:-$DV_TOP}"
    export DV_VERDI_FILELIST="${DV_VERDI_FILELIST:-}"
    export DV_VERDI_WORK_DIR="${DV_VERDI_WORK_DIR:-}"
    export DV_VERDI_SOURCE_OPTS="${DV_VERDI_SOURCE_OPTS:-}"
    export DV_DEFAULT_PLUSARGS="${DV_DEFAULT_PLUSARGS:-}"
    export DV_DUT_MODE="${DV_DUT_MODE:-${DUT_MODE:-rtl}}"
    export DV_SOURCE_MODE="${DV_SOURCE_MODE:-${SOURCE_MODE:-project}}"
    export DV_REQUIRE_UVM_SUMMARY="${DV_REQUIRE_UVM_SUMMARY:-1}"
    export DV_PASS_REGEX="${DV_PASS_REGEX:-UVM Report Summary|UVM_REPORT_SUMMARY|UVM/REPORT/(SERVER|CATCHER)}"

    export TOP="$DV_TOP"
    export FILELIST="$(runner_project_abs_path "$DV_FILELIST")"
    export TEST_LIST_FILE="$(runner_project_abs_path "$DV_TESTPLAN")"
    export OUT_DIR="$(runner_project_abs_path "$DV_OUT_ROOT")"
    export UVM_MODE="$DV_UVM_MODE"
    export UVM_HOME="$DV_UVM_HOME"
    export UVM_USE_DPI="$DV_UVM_USE_DPI"
    export EXTRA_COMPILE_OPTS="$DV_EXTRA_COMPILE_OPTS"
    export EXTRA_RUN_OPTS="$DV_EXTRA_RUN_OPTS"
    export RUNNER_OUT_DIR="$OUT_DIR"
    export DV_VERDI_FILELIST="${DV_VERDI_FILELIST:-$FILELIST}"
    export DV_VERDI_WORK_DIR="${DV_VERDI_WORK_DIR:-${COMPILE_WORK_DIR:-$RUNNER_ROOT}}"

    if declare -F dv_project_prepare_testplan >/dev/null 2>&1; then
        dv_project_prepare_testplan || {
            echo "[ERROR] Project test-plan preparation failed" >&2
            return 2
        }
    fi
}

runner_project_run_command() {
    local label="$1" command="$2"
    [[ -n "$command" ]] || return 0
    printf '[INFO] Project hook: %s\n' "$label"
    (cd "$DV_PROJECT_ROOT" && bash -lc "$command")
}

runner_project_preflight() {
    if declare -F dv_project_preflight >/dev/null 2>&1; then
        dv_project_preflight
    else
        runner_project_run_command preflight "${DV_PRECHECK_CMD:-}"
    fi
}

runner_project_generate() {
    if declare -F dv_project_generate >/dev/null 2>&1; then
        dv_project_generate "$@"
    elif [[ -n "${DV_GENERATE_CMD:-}" ]]; then
        DV_GENERATE_ARGS="$*" runner_project_run_command generate "$DV_GENERATE_CMD ${*:-}"
    else
        printf '[ERROR] Project does not define DV_GENERATE_CMD or dv_project_generate()\n' >&2
        return 2
    fi
}

runner_project_pre_run() {
    local test_name="$1" seed="$2" case_dir="$3"
    export DV_ACTIVE_TEST="$test_name" DV_ACTIVE_SEED="$seed" DV_ACTIVE_CASE_DIR="$case_dir"
    export DV_PROJECT_RUN_PLUSARGS=''
    if declare -F dv_project_pre_run >/dev/null 2>&1; then
        dv_project_pre_run "$test_name" "$seed" "$case_dir"
    elif [[ -n "${DV_PRE_RUN_CMD:-}" ]]; then
        runner_project_run_command pre-run "$DV_PRE_RUN_CMD"
    fi
}

runner_project_post_run() {
    local test_name="$1" seed="$2" case_dir="$3" rc="$4"
    export DV_ACTIVE_TEST="$test_name" DV_ACTIVE_SEED="$seed" DV_ACTIVE_CASE_DIR="$case_dir" DV_ACTIVE_RC="$rc"
    if declare -F dv_project_post_run >/dev/null 2>&1; then
        dv_project_post_run "$test_name" "$seed" "$case_dir" "$rc"
    elif [[ -n "${DV_POST_RUN_CMD:-}" ]]; then
        runner_project_run_command post-run "$DV_POST_RUN_CMD"
    fi
}

runner_project_print() {
    printf '%-24s %s\n' \
        PROJECT "$DV_PROJECT_NAME" CONFIG "${RUNNER_PROJECT_CONFIG:-(none)}" \
        PROJECT_ROOT "$DV_PROJECT_ROOT" SIMULATOR "$DV_SIMULATOR" \
        TOP "$DV_TOP" FILELIST "$FILELIST" TESTPLAN "$TEST_LIST_FILE" \
        OUT_ROOT "$OUT_DIR" UVM_MODE "$DV_UVM_MODE" SCHEDULER_OWNER runner
}
