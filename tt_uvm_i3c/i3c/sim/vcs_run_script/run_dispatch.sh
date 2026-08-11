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
# File        : run_dispatch.sh
# Description : TT UVM I3C simulation support file.
# Authors     : Duy Huynh, Dang Thai
# Date        : 2026-08-11
#
# *****************************************************************************


RUNNER_SCRIPT_DIR="${RUNNER_SCRIPT_DIR:-$RUNNER_ROOT/sim/vcs_run_script}"

# shellcheck source=scripts/common.sh
source "$RUNNER_SCRIPT_DIR/common.sh"
source "$RUNNER_SCRIPT_DIR/common_scheduler.sh"
source "$RUNNER_SCRIPT_DIR/common_active_jobs.sh"
source "$RUNNER_SCRIPT_DIR/common_live_output.sh"
source "$RUNNER_SCRIPT_DIR/common_reporting.sh"
source "$RUNNER_SCRIPT_DIR/common_attempt_retry.sh"
source "$RUNNER_SCRIPT_DIR/run_compile.sh"
source "$RUNNER_SCRIPT_DIR/run_test.sh"
source "$RUNNER_SCRIPT_DIR/run_regression.sh"
source "$RUNNER_SCRIPT_DIR/merge_cov.sh"
source "$RUNNER_SCRIPT_DIR/run_coverage.sh"
source "$RUNNER_SCRIPT_DIR/open_wave.sh"
source "$RUNNER_SCRIPT_DIR/clean.sh"
source "$RUNNER_SCRIPT_DIR/summary.sh"
source "$RUNNER_SCRIPT_DIR/check_config.sh"

runner_list_tests() {
    local test_file
    test_file="$(runner_make_value print-test-list)"
    [[ "$test_file" == /* ]] || test_file="$RUNNER_ROOT/$test_file"
    [[ -r "$test_file" ]] || { runner_die "Test-list file is not readable: $test_file"; return $?; }
    awk -F'|' '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ {next}
        {printf "%-32s group=%-16s level=%-8s seeds=%s tags=%s\n", $1, $2, $3, $6, $8}
    ' "$test_file"
}

runner_run_generate() {
    runner_project_generate "$@" || return $?
    [[ -r "$FILELIST" ]] || {
        runner_error "Generated compile filelist is missing: $FILELIST"
        return 2
    }
    [[ -r "$TEST_LIST_FILE" ]] ||
        runner_warn "Generated test plan is missing: $TEST_LIST_FILE"
    runner_info "Generation completed"
}

runner_dispatch_detached() {
    local -a args=("$@") filtered=()
    local arg runner_entrypoint
    for arg in "${args[@]}"; do
        [[ "$arg" == '--detach' ]] || filtered+=("$arg")
    done
    runner_prepare_out_dir
    local log_dir="$(runner_out_dir)/logs/detached"
    local log_file="$log_dir/${filtered[0]:-command}_$(runner_timestamp).log"
    mkdir -p "$log_dir"
    runner_entrypoint="${DV_RUNNER_ENTRYPOINT:?DV_RUNNER_ENTRYPOINT is not set}"
    nohup env DV_RUNNER_REENTRY=1 "$runner_entrypoint" \
        "${filtered[@]}" >"$log_file" 2>&1 < /dev/null &
    local pid=$!
    runner_register_job "$pid" "detached.${filtered[0]:-command}" "$log_file"
    runner_info "Detached pid=$pid log=$log_file"
}

runner_dispatch_command() {
    local command="${1:-help}"
    (($# == 0)) || shift

    if [[ "${1:-}" == '-h' || "${1:-}" == '--help' ]]; then
        case "$command" in
            view|wave) ;;
            *) runner_print_help "$command"; return $? ;;
        esac
    fi

    local arg
    for arg in "$@"; do
        if [[ "$arg" == '--detach' ]]; then
            runner_dispatch_detached "$command" "$@"
            return $?
        fi
    done

    case "$command" in
        help|-h|--help) runner_print_help "$@" ;;
        generate|gen) runner_run_generate "$@" ;;
        comp|compile) runner_run_compile "$@" ;;
        test) runner_run_test "$@" ;;
        regression|regress) runner_run_regression "$@" ;;
        coverage|cov) runner_run_coverage "$@" ;;
        merge-cov) runner_merge_coverage "$@" ;;
        wave|view) runner_open_wave "$@" ;;
        summary) runner_show_summary "$@" ;;
        list-tests) runner_list_tests ;;
        doctor|check) runner_check_config ;;
        clean) runner_clean "$@" ;;
        *)
            runner_error "Unknown command: $command"
            runner_print_help >&2
            return 2
            ;;
    esac
}

runner_dispatch() {
    local command="${1:-help}" start rc=0
    local -a original=("$@")
    case "$command" in
        help|-h|--help)
            runner_dispatch_command "${original[@]}"
            return $?
            ;;
    esac
    if [[ "${original[1]:-}" == '-h' || "${original[1]:-}" == '--help' ]]; then
        runner_dispatch_command "${original[@]}"
        return $?
    fi
    start="$(date +%s)"
    runner_report_command_start "$command" "${original[@]:1}"
    runner_dispatch_command "${original[@]}" || rc=$?
    runner_report_command_end "$command" "$rc" "$start"
    return "$rc"
}
