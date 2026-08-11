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
# File        : common_reporting.sh
# Description : TT UVM I3C simulation support file.
# Authors     : Duy Huynh, Dang Thai
# Date        : 2026-08-11
#
# *****************************************************************************


runner_report_path() {
    local path="$1"
    if [[ "$path" == "$RUNNER_ROOT/"* ]]; then printf '%s\n' "${path#"$RUNNER_ROOT/"}"
    else printf '%s\n' "$path"
    fi
}

runner_report_duration() {
    local seconds="${1:-0}"
    if declare -F runner_format_duration >/dev/null 2>&1; then runner_format_duration "$seconds"
    else printf '%ss' "$seconds"
    fi
}

runner_report_command_start() {
    local command="$1"
    shift
    [[ "${RUNNER_REPORT_QUIET:-0}" != 1 ]] || return 0
    runner_panel_begin "Command Execution"
    runner_panel_value Command "$command"
    runner_panel_value Project "${DV_PROJECT_NAME:-unknown}"
    runner_panel_value Simulator "${DV_SIMULATOR:-unknown}"
    runner_panel_value "DUT Mode" "${DV_DUT_MODE:-unknown}"
    runner_panel_value "Source Mode" "${DV_SOURCE_MODE:-unknown}"
    runner_panel_value Started "$(runner_display_time)"
    runner_panel_value Arguments "$(runner_command_string "$@")"
    runner_panel_end
}

runner_report_command_end() {
    local command="$1" rc="$2" start_epoch="$3" status=PASS
    ((rc == 0)) || status=FAIL
    [[ "${RUNNER_REPORT_QUIET:-0}" != 1 ]] || return 0
    runner_panel_begin "Command Execution Summary"
    runner_panel_value Command "$command"
    runner_panel_value Status "$status"
    runner_panel_value "Return Code" "$rc"
    runner_panel_value Duration "$(runner_report_duration "$(( $(date +%s) - start_epoch ))")"
    runner_panel_value Completed "$(runner_display_time)"
    runner_panel_end
}

runner_report_uvm_configuration() {
    [[ "${RUNNER_REPORT_QUIET:-0}" != 1 ]] || return 0
    runner_panel_begin "UVM Library Configuration"
    runner_panel_value Mode "${DV_UVM_MODE:-unknown}"
    runner_panel_value Home "${DV_UVM_HOME:-(builtin)}"
    runner_panel_value "Use DPI" "${DV_UVM_USE_DPI:-0}"
    runner_panel_value Simulator "${DV_SIMULATOR:-unknown}"
    runner_panel_end
}

runner_report_compile_plan() {
    local run_id="$1" scheduler="$2" cpus="$3" build_dir="$4" log_file="$5" cov="$6" dump_format="$7"
    local timeout_sec="$8" idle_timeout_sec="$9" command_file="${10}" stats entries bytes tool_path disk_free license_state=missing
    [[ "${RUNNER_REPORT_QUIET:-0}" != 1 ]] || return 0
    stats="$(runner_filelist_stats "$FILELIST")"; entries="${stats%%|*}"; bytes="${stats#*|}"
    tool_path="$(command -v "${VCS:-vcs}" 2>/dev/null || printf not-found)"
    disk_free="$(df -Pk "$(dirname "$build_dir")" 2>/dev/null | awk 'NR==2 {printf "%.1f GiB", $4/1048576}')"
    [[ -n "${SNPSLMD_LICENSE_FILE:-${LM_LICENSE_FILE:-}}" ]] && license_state=configured
    runner_panel_begin "Compile Execution Plan"
    runner_panel_value "Run ID" "$run_id"
    runner_panel_value Project "${DV_PROJECT_NAME:-unknown}"
    runner_panel_value "DUT Mode" "${DV_DUT_MODE:-unknown}"
    runner_panel_value "Source Mode" "${DV_SOURCE_MODE:-unknown}"
    runner_panel_value Top "${DV_TOP:-unknown}"
    runner_panel_value Filelist "$FILELIST"
    runner_panel_value "Filelist Entries" "$entries"
    runner_panel_value "Filelist Bytes" "$bytes"
    runner_panel_value Scheduler "$scheduler"
    runner_panel_value "Compile CPUs" "$cpus"
    runner_panel_value "VCS Compile Jobs" "$cpus"
    runner_panel_value "Tool Path" "$tool_path"
    runner_panel_value "License Env" "$license_state"
    runner_panel_value "Disk Free" "${disk_free:-unknown}"
    runner_panel_value "Build Dir" "$build_dir"
    runner_panel_value "Compile Log" "$log_file"
    runner_panel_value Coverage "$cov"
    runner_panel_value "Dump Format" "$dump_format"
    runner_panel_value Timeout "${timeout_sec}s"
    runner_panel_value "Idle Timeout" "${idle_timeout_sec}s"
    runner_panel_value "Command File" "$command_file"
    runner_panel_value "Build Isolation" "private per burst/test run"
    runner_panel_end
}

runner_report_test_plan() {
    local test_name="$1" seeds="$2" jobs="$3" scheduler="$4" cpus="$5" verbosity="$6" cov="$7" dump_format="$8"
    local do_compile="$9" retry_max="${10}" run_dir="${11}" heartbeat="${12}" hang_warn="${13}" hang_kill="${14}" plusargs="${15}"
    [[ "${RUNNER_REPORT_QUIET:-0}" != 1 ]] || return 0
    runner_panel_begin "Single Test Execution Plan"
    runner_panel_value Test "$test_name"
    runner_panel_value Seeds "$seeds"
    runner_panel_value Parallel "jobs=$jobs"
    runner_panel_value Scheduler "$scheduler"
    runner_panel_value CPUs "$cpus"
    runner_panel_value Verbosity "$verbosity"
    runner_panel_value Coverage "$cov"
    runner_panel_value "Dump Format" "$dump_format"
    runner_panel_value Compile "$do_compile"
    runner_panel_value "Seed Attempts" "$retry_max"
    runner_panel_value "Run Dir" "$run_dir"
    runner_panel_value Heartbeat "${heartbeat}s"
    runner_panel_value "Hang Guard" "warn=${hang_warn}s kill=${hang_kill}s"
    runner_panel_value Plusargs "${plusargs:-(none)}"
    runner_panel_end
}

runner_report_regression_plan() {
    local run_id="$1" burst_count="$2" worker="$3" burst_max="$4" scheduler="$5" retry_schedule="$6"
    local attempts="$7" dump_format="$8" cov="$9" manifest="${10}"
    [[ "${RUNNER_REPORT_QUIET:-0}" != 1 ]] || return 0
    runner_panel_begin "Regression Execution Plan"
    runner_panel_value "Run ID" "$run_id"
    runner_panel_value Bursts "$burst_count"
    runner_panel_value "Seed Workers" "$worker"
    runner_panel_value "Burst Parallel" "$burst_max"
    runner_panel_value Scheduler "$scheduler"
    runner_panel_value "Retry Schedule" "$retry_schedule"
    runner_panel_value "Burst Attempts" "$attempts"
    runner_panel_value Coverage "$cov"
    runner_panel_value "Dump Format" "$dump_format"
    runner_panel_value "Compile Policy" "independent compile per burst"
    runner_panel_value Manifest "$manifest"
    runner_panel_end
}

runner_log_metric_count() {
    local file="$1" metric="$2" value plain_errors uvm_errors uvm_fatals uvm_events
    file="$(runner_log_for_analysis "$file")"
    [[ -f "$file" ]] || { printf '0\n'; return; }
    case "$metric" in
        UVM_WARNING|UVM_ERROR|UVM_FATAL)
            value="$(grep -E "${metric}[[:space:]]*:[[:space:]]*[0-9]+" "$file" 2>/dev/null | tail -n 1 | sed -E 's/.*:[[:space:]]*([0-9]+).*/\1/')"
            ;;
        SVA_ERROR)
            if grep -Eiq "${RUNNER_SVA_MARKER_REGEX:-SVA:[[:space:]]*[[:alnum:]_.$:/-]+}" "$file" 2>/dev/null; then
                value="$(grep -Eic "${RUNNER_SVA_MARKER_REGEX:-SVA:[[:space:]]*[[:alnum:]_.$:/-]+}" "$file" 2>/dev/null || true)"
            else
                value="$(grep -Eic "${RUNNER_SVA_FAILURE_REGEX:-Assertion.*(fail|error)|assertion[[:space:]_-]*failed}" "$file" 2>/dev/null || true)"
            fi
            ;;
        PLAIN_ERROR)
            value="$(grep -Eic "$RUNNER_PLAIN_ERROR_REGEX" "$file" 2>/dev/null || true)"
            ;;
        UVM_EVENT)
            value="$(grep -Eic "$RUNNER_UVM_EVENT_REGEX" "$file" 2>/dev/null || true)"
            ;;
        ERROR_TOTAL)
            plain_errors="$(runner_log_metric_count "$file" PLAIN_ERROR)"
            uvm_errors="$(runner_log_metric_count "$file" UVM_ERROR)"
            uvm_fatals="$(runner_log_metric_count "$file" UVM_FATAL)"
            if ((uvm_errors + uvm_fatals == 0)); then
                uvm_events="$(runner_log_metric_count "$file" UVM_EVENT)"
            else
                uvm_events=0
            fi
            value=$((plain_errors + uvm_errors + uvm_fatals + uvm_events))
            ;;
    esac
    printf '%s\n' "${value:-0}"
}

runner_collect_log_metrics() {
    local file="$1"
    RUNNER_METRIC_UVM_WARNING="$(runner_log_metric_count "$file" UVM_WARNING)"
    RUNNER_METRIC_UVM_ERROR="$(runner_log_metric_count "$file" UVM_ERROR)"
    RUNNER_METRIC_UVM_FATAL="$(runner_log_metric_count "$file" UVM_FATAL)"
    RUNNER_METRIC_SVA_ERROR="$(runner_log_metric_count "$file" SVA_ERROR)"
    RUNNER_METRIC_SCOREBOARD_FAILED=0
    runner_log_has_scoreboard_failure "$file" && RUNNER_METRIC_SCOREBOARD_FAILED=1
    RUNNER_METRIC_ERROR_TOTAL="$(runner_log_metric_count "$file" ERROR_TOTAL)"
}

runner_report_extract_failures() {
    local log_file="$1" include_warnings="${2:-0}" pattern assertion_pattern
    log_file="$(runner_log_for_analysis "$log_file")"
    [[ -f "$log_file" ]] || { printf '[missing log] %s\n' "$log_file"; return; }
    assertion_pattern="${RUNNER_SVA_FAILURE_REGEX:-Assertion.*(fail|error)|assertion[[:space:]_-]*failed}"
    if grep -Eiq "${RUNNER_SVA_MARKER_REGEX:-SVA:[[:space:]]*[[:alnum:]_.$:/-]+}" "$log_file" 2>/dev/null; then
        assertion_pattern="${RUNNER_SVA_MARKER_REGEX:-SVA:[[:space:]]*[[:alnum:]_.$:/-]+}"
    fi
    pattern="${RUNNER_UVM_FAILURE_REGEX}|${RUNNER_PLAIN_ERROR_REGEX}|${assertion_pattern}|${RUNNER_SCOREBOARD_FAILURE_REGEX}|TEST[[:space:]_-]*FAIL|Fatal License Error|Cannot connect to the license server|SCL-[0-9]+|Segmentation fault|Internal error|syntax error"
    ((include_warnings)) && pattern="${pattern}|UVM_WARNING[[:space:]]*:[[:space:]]*[1-9]|^[[:space:]]*Warning:"
    grep -Ein "$pattern" "$log_file" 2>/dev/null | tail -n 80 || true
}

runner_report_assertion_failures() {
    local log_file="$1" pattern
    log_file="$(runner_log_for_analysis "$log_file")"
    [[ -f "$log_file" ]] || return 0
    pattern="${RUNNER_SVA_MARKER_REGEX:-SVA:[[:space:]]*[[:alnum:]_.$:/-]+}"
    if ! grep -Eiq "$pattern" "$log_file" 2>/dev/null; then
        pattern="${RUNNER_SVA_FAILURE_REGEX:-Assertion.*(fail|error)|assertion[[:space:]_-]*failed}"
    fi
    grep -Ein "$pattern" "$log_file" 2>/dev/null | tail -n 80 || true
}

runner_report_compile_categories() {
    local file="$1" syntax license scheduler disk internal undefined
    syntax="$(grep -Eic 'syntax error|Error-\[SE\]|unexpected token' "$file" 2>/dev/null || true)"
    license="$(grep -Eic 'Fatal License Error|license.*(fail|denied|unavailable)|Cannot connect to the license server|SCL-[0-9]+' "$file" 2>/dev/null || true)"
    scheduler="$(grep -Eic 'srun:.*(error|failed)|slurmstepd: error|scheduler.*failed' "$file" 2>/dev/null || true)"
    disk="$(grep -Eic 'No space left on device|Disk quota exceeded' "$file" 2>/dev/null || true)"
    internal="$(grep -Eic 'Internal error|Segmentation fault|core dumped' "$file" 2>/dev/null || true)"
    undefined="$(grep -Eic 'Undefined|not defined|could not be bound|Package .* not found' "$file" 2>/dev/null || true)"
    printf 'Syntax=%s License=%s Scheduler=%s Disk=%s Internal=%s Undefined=%s\n' "$syntax" "$license" "$scheduler" "$disk" "$internal" "$undefined"
}

runner_write_artifact_index() {
    local root="$1" output="${2:-$1/summary/artifacts.tsv}" path kind
    [[ -d "$root" ]] || return 0
    mkdir -p "$(dirname "$output")"
    printf 'kind|path|bytes|modified\n' > "$output"
    while IFS= read -r -d '' path; do
        case "$path" in
            *.clean.log) kind=clean_log ;;
            *.log) kind=log ;;
            *.tsv) kind=status ;;
            *.meta) kind=metadata ;;
            *.sh) kind=command ;;
            *.fsdb|*.vcd|*.vpd) kind=wave ;;
            *.html|*.txt) kind=report ;;
            *) kind=file ;;
        esac
        printf '%s|%s|%s|%s\n' "$kind" "$path" "$(wc -c < "$path" 2>/dev/null || printf 0)" \
            "$(date -r "$path" -Is 2>/dev/null || printf unknown)" >> "$output"
    done < <(find "$root" -type f ! -path "$output" -print0 2>/dev/null)
    while IFS= read -r -d '' path; do
        printf 'coverage_db|%s|0|%s\n' "$path" "$(date -r "$path" -Is 2>/dev/null || printf unknown)" >> "$output"
    done < <(find "$root" -type d -name '*.vdb' -print0 2>/dev/null)
}

runner_report_terminal_dashboard() {
    local title="$1" status="$2" total="$3" passed="$4" failed="$5" duration="$6" summary="$7" errors="${8:-}"
    [[ "${RUNNER_REPORT_QUIET:-0}" != 1 ]] || return 0
    printf '\n================================================================================\n'
    printf '  %s\n' "$title"
    printf '================================================================================\n'
    printf ' Status       : %s\n' "$status"
    printf ' Total        : %s\n' "$total"
    printf ' Passed       : %s\n' "$passed"
    printf ' Failed       : %s\n' "$failed"
    printf ' Duration     : %s\n' "$duration"
    printf ' Summary Log  : %s\n' "$(runner_report_path "$summary")"
    [[ -z "$errors" ]] || printf ' Errors Log   : %s\n' "$(runner_report_path "$errors")"
    printf '================================================================================\n'
}

runner_report_compile() {
    local run_id="$1" run_dir="$2" log_file="$3" rc="$4" start_epoch="$5"
    local summary_dir summary_file errors_file status=PASS now duration
    summary_dir="$run_dir/summary"
    summary_file="$summary_dir/compile.log"
    errors_file="$summary_dir/compile.errors.log"
    ((rc == 0)) || status=FAIL
    now="$(date +%s)"; duration="$(runner_report_duration "$((now - start_epoch))")"
    mkdir -p "$summary_dir"
    {
        printf '================================================================================\n'
        printf 'Compile Summary\n'
        printf 'Run ID       : %s\n' "$run_id"
        printf 'Project      : %s\n' "${DV_PROJECT_NAME:-unknown}"
        printf 'Status       : %s\n' "$status"
        printf 'Return Code  : %s\n' "$rc"
        printf 'Duration     : %s\n' "$duration"
        printf 'Compile Log  : %s\n' "$(runner_report_path "$log_file")"
        printf 'Error Class  : %s\n' "$(runner_report_compile_categories "$log_file")"
        printf 'Completed    : %s\n' "$(date -Is)"
        printf '================================================================================\n'
    } > "$summary_file"
    if ((rc != 0)); then
        {
            printf '================================================================================\n'
            printf 'Compile Error Extract\n'
            printf 'Source Log   : %s\n' "$(runner_report_path "$log_file")"
            printf '%s\n' '--------------------------------------------------------------------------------'
            runner_report_extract_failures "$log_file" 1
            printf '================================================================================\n'
        } > "$errors_file"
    else
        rm -f "$errors_file"
    fi
    runner_write_artifact_index "$run_dir"
    runner_report_terminal_dashboard "Compile Summary" "$status" 1 "$((rc == 0 ? 1 : 0))" "$((rc == 0 ? 0 : 1))" "$duration" "$summary_file" "$([[ -f "$errors_file" ]] && printf '%s' "$errors_file")"
    if [[ "${RUNNER_REPORT_QUIET:-0}" != 1 ]]; then
        if ((rc == 0)); then printf '[PASS] COMPILE project=%s run=%s\n' "${DV_PROJECT_NAME:-unknown}" "$run_id"
        else printf '[FAIL] COMPILE project=%s run=%s rc=%s log=%s\n' "${DV_PROJECT_NAME:-unknown}" "$run_id" "$rc" "$(runner_report_path "$log_file")" >&2
        fi
    fi
}

runner_failure_causes() {
    local rc="$1" reason="$2" log_file="$3"
    local uvm_errors=0 uvm_fatals=0 sva_errors=0 plain_errors=0 cause joined=''
    local -a causes=()

    if [[ "$reason" == COMPILE_FAIL ]]; then
        printf 'COMPILE:RC=%s\n' "$rc"
        return
    fi

    uvm_errors="$(runner_log_metric_count "$log_file" UVM_ERROR)"
    uvm_fatals="$(runner_log_metric_count "$log_file" UVM_FATAL)"
    sva_errors="$(runner_log_metric_count "$log_file" SVA_ERROR)"
    plain_errors="$(runner_log_metric_count "$log_file" PLAIN_ERROR)"

    ((uvm_errors == 0)) || causes+=("RUN:UVM_ERROR=$uvm_errors")
    ((uvm_fatals == 0)) || causes+=("RUN:UVM_FATAL=$uvm_fatals")
    ((sva_errors == 0)) || causes+=("ASSERT=$sva_errors")

    case "$reason" in
        TIMEOUT) causes+=("RUN:TIMEOUT") ;;
        ERROR_FAIL)
            ((plain_errors == 0)) && causes+=("RUN:ERROR") || causes+=("RUN:ERROR=$plain_errors")
            ;;
        TEST_FAIL) causes+=("RUN:TEST_FAIL") ;;
        SCOREBOARD_FAIL) causes+=("RUN:CHECKER_FAIL") ;;
        LICENSE_FAIL) causes+=("INFRA:LICENSE") ;;
        DISK_FAIL) causes+=("INFRA:DISK") ;;
        SCHEDULER_FAIL) causes+=("INFRA:SCHEDULER") ;;
        TOOL_FAIL) causes+=("INFRA:TOOL") ;;
        INFRA_FAIL) causes+=("INFRA:RUN") ;;
        UVM_FAIL)
            ((uvm_errors + uvm_fatals > 0)) || causes+=("RUN:UVM")
            ;;
        ASSERT_FAIL)
            ((sva_errors > 0)) || causes+=("ASSERT")
            ;;
        UNKNOWN)
            ((rc == 0)) || causes+=("RUN:RC=$rc")
            ;;
    esac

    ((${#causes[@]} > 0)) || causes+=("RUN:RC=$rc")
    for cause in "${causes[@]}"; do
        joined="${joined:+$joined, }$cause"
    done
    printf '%s\n' "$joined"
}

runner_report_case_result() {
    local status="$1" burst="$2" attempt="$3" test_name="$4" seed="$5" rc="$6" reason="$7" log_file="$8"
    [[ "$burst" == B* ]] || burst="$(printf 'B%03d' "${burst:-1}")"
    [[ "$attempt" == A* ]] || attempt="$(printf 'A%03d' "${attempt:-1}")"
    if [[ "$status" == PASS ]]; then
        printf '[PASS] %s %s test=%s seed=%s\n' "$burst" "$attempt" "$test_name" "$seed"
    else
        printf '[FAIL] %s %s test=%s seed=%s\n' "$burst" "$attempt" "$test_name" "$seed" >&2
        printf '       reasons=[%s]\n' "$(runner_failure_causes "$rc" "$reason" "$log_file")" >&2
        printf '       log=%s\n' "$(runner_report_path "$log_file")" >&2
    fi
}

runner_report_failure_link() {
    local index="$1" burst="$2" attempt="$3" test_name="$4" seed="$5" rc="$6" reason="$7" log_file="$8"
    [[ "$burst" == B* ]] || burst="$(printf 'B%03d' "${burst:-1}")"
    [[ "$attempt" == A* ]] || attempt="$(printf 'A%03d' "${attempt:-1}")"
    printf '[%s] %s %s test=%s seed=%s\n' "$index" "$burst" "$attempt" "$test_name" "$seed"
    printf '    reasons=[%s]\n' "$(runner_failure_causes "$rc" "$reason" "$log_file")"
    printf '    log=%s\n' "$(runner_report_path "$log_file")"
}

runner_report_seed_result() {
    local status="$1" test_name="$2" seed="$3" attempt="$4" rc="$5" reason="$6" log_file="$7"
    local warnings="${8:-0}" errors="${9:-0}" fatals="${10:-0}" sva_errors="${11:-0}" scoreboard_failed="${12:-0}"
    local dump_status="${13:-DISABLED}" dump_file="${14:-}"
    local position="${15:-1}" total="${16:-1}" burst="${TEST_BURST_ID:-B001}"
    [[ "${RUNNER_REPORT_QUIET:-0}" != 1 ]] || return 0
    runner_report_case_result "$status" "${burst:-B001}" "$attempt" "$test_name" "$seed" "$rc" "$reason" "$log_file"
    if [[ "$dump_status" == MISSING ]]; then
        printf '[ARTIFACT] DUMP=MISSING TEST=%s SEED=%s EXPECTED=%s\n' \
            "$test_name" "$seed" "$(runner_report_path "$dump_file")" >&2
    elif [[ "$dump_status" == CREATED ]]; then
        printf '[ARTIFACT] DUMP=CREATED TEST=%s SEED=%s FILE=%s\n' \
            "$test_name" "$seed" "$(runner_report_path "$dump_file")"
    fi
}

runner_report_test() {
    local run_id="$1" test_name="$2" run_dir="$3" seeds_file="$4" start_epoch="$5" include_warnings="${6:-0}"
    local summary_dir latest_file summary_file errors_file quick_links_file
    local total passed failed status now duration seed attempt result rc reason elapsed log_file index=0
    local warnings errors fatals sva_errors scoreboard_failed dump_status dump_file row_error total_w=0 total_e=0 total_f=0 total_sva=0 total_error=0 retried=0 missing_dumps=0
    summary_dir="$run_dir/summary"
    latest_file="$summary_dir/seeds.latest.tsv"
    summary_file="$summary_dir/test.log"
    errors_file="$summary_dir/test.errors.log"
    quick_links_file="$summary_dir/failure_quick_links.log"
    mkdir -p "$summary_dir"
    awk -F'|' 'NR>1 && NF>=7 {if(!seen[$1]++) order[++n]=$1; row[$1]=$0} END {for(i=1;i<=n;i++) print row[order[i]]}' \
        "$seeds_file" > "$latest_file"
    total="$(wc -l < "$latest_file" | tr -d '[:space:]')"
    passed="$(awk -F'|' '$3=="PASS" {n++} END {print n+0}' "$latest_file")"
    failed=$((total - passed)); status=PASS; ((failed == 0)) || status=FAIL
    now="$(date +%s)"; duration="$(runner_report_duration "$((now - start_epoch))")"
    {
        printf '================================================================================\n'
        printf 'Single Test Summary\n'
        printf 'Run ID       : %s\n' "$run_id"
        printf 'Test         : %s\n' "$test_name"
        printf 'Status       : %s\n' "$status"
        printf 'Total Seeds  : %s\n' "$total"
        printf 'Passed       : %s\n' "$passed"
        printf 'Failed       : %s\n' "$failed"
        while IFS='|' read -r seed attempt result rc reason elapsed log_file warnings errors fatals sva_errors scoreboard_failed dump_status dump_file; do
            total_w=$((total_w + ${warnings:-0})); total_e=$((total_e + ${errors:-0})); total_f=$((total_f + ${fatals:-0}))
            total_sva=$((total_sva + ${sva_errors:-0}))
            row_error="$(runner_log_metric_count "$log_file" ERROR_TOTAL)"
            total_error=$((total_error + row_error))
            [[ "$dump_status" != MISSING ]] || missing_dumps=$((missing_dumps + 1))
            # "Pass after retry": only a non-first attempt that actually PASSED,
            # matching the regression metric (see runner_report_regression's
            # $result==PASS && attempt!=A001 rule). Without the PASS guard this
            # counted every retry, so a failing test wrongly showed retried>0.
            [[ "${attempt#A}" == 001 || "$result" != PASS ]] || retried=$((retried + 1))
        done < "$latest_file"
        printf 'Pass After Retry : %s\n' "$retried"
        printf 'UVM Warning/Error/Fatal : %s/%s/%s\n' "$total_w" "$total_e" "$total_f"
        printf 'SVA Error    : %s\n' "$total_sva"
        printf 'Error Total  : %s\n' "$total_error"
        printf 'Missing Dumps : %s\n' "$missing_dumps"
        printf 'Duration     : %s\n' "$duration"
        printf '%s\n' '--------------------------------------------------------------------------------'
        while IFS='|' read -r seed attempt result rc reason elapsed log_file warnings errors fatals sva_errors scoreboard_failed dump_status dump_file; do
            index=$((index + 1))
            printf '[SEED-RESULT %s/%s]\n' "$index" "$total"
            printf 'Status       : %s\nTest         : %s\nSeed         : %s\nAttempt      : %s\n' "$result" "$test_name" "$seed" "$attempt"
            printf 'RC           : %s\nReason       : %s\nTime         : %s\nDetail Log   : %s\n' "$rc" "$reason" "$(runner_report_duration "$elapsed")" "$(runner_report_path "$log_file")"
            row_error="$(runner_log_metric_count "$log_file" ERROR_TOTAL)"
            printf 'UVM W/E/F    : %s/%s/%s\nSVA Error    : %s\nError Total  : %s\n' \
                "${warnings:-0}" "${errors:-0}" "${fatals:-0}" "${sva_errors:-0}" "$row_error"
            printf 'Dump Status  : %s\nDump File    : %s\n' "${dump_status:-DISABLED}" "$(runner_report_path "$dump_file")"
            printf '%s\n' '--------------------------------------------------------------------------------'
        done < "$latest_file"
        printf 'Completed    : %s\n' "$(date -Is)"
        printf '================================================================================\n'
    } > "$summary_file"
    : > "$errors_file"
    while IFS='|' read -r seed attempt result rc reason elapsed log_file warnings errors fatals sva_errors scoreboard_failed dump_status dump_file; do
        [[ "$result" == FAIL ]] || continue
        {
            printf '================================================================================\n'
            printf 'TEST=%s SEED=%s ATTEMPT=%s RC=%s REASON=%s\n' "$test_name" "$seed" "$attempt" "$rc" "$reason"
            printf 'LOG=%s\n' "$(runner_report_path "$log_file")"
            printf '%s\n' '--------------------------------------------------------------------------------'
            runner_report_extract_failures "$log_file" "$include_warnings"
        } >> "$errors_file"
    done < "$latest_file"
    [[ -s "$errors_file" ]] || rm -f "$errors_file"
    : > "$quick_links_file"
    index=0
    while IFS='|' read -r seed attempt result rc reason elapsed log_file warnings errors fatals sva_errors scoreboard_failed dump_status dump_file; do
        [[ "$result" == FAIL ]] || continue
        index=$((index + 1))
        runner_report_failure_link "$index" "${TEST_BURST_ID:-B001}" "$attempt" "$test_name" "$seed" "$rc" "$reason" "$log_file" \
            >> "$quick_links_file"
    done < "$latest_file"
    if [[ -s "$quick_links_file" ]]; then
        {
            printf '%s\nFailure Quick Links\n%s\n' '--------------------------------------------------------------------------------' '--------------------------------------------------------------------------------'
            cat "$quick_links_file"
        } >> "$summary_file"
    else
        rm -f "$quick_links_file"
    fi
    runner_write_artifact_index "$run_dir"
    runner_report_terminal_dashboard "Single Test Summary: $test_name" "$status" "$total" "$passed" "$failed" "$duration" "$summary_file" "$([[ -f "$errors_file" ]] && printf '%s' "$errors_file")"
    if [[ "${RUNNER_REPORT_QUIET:-0}" != 1 ]]; then
        if [[ -f "$quick_links_file" ]]; then
            printf '\nFailure Quick Links\n%s\n' '--------------------------------------------------------------------------------'
            cat "$quick_links_file"
        fi
    fi
}

runner_coverage_parse_metrics() {
    local report_dir="$1" output="$2" dashboard
    if [[ -f "$report_dir/dashboard.txt" ]]; then
        dashboard="$report_dir/dashboard.txt"
        awk '
        /Total Coverage Summary/ {in_summary=1; next}
        in_summary && $1=="SCORE" {
            for (i=1; i<=NF; i++) {
                name=tolower($i)
                if (name=="tgl") name="toggle"
                column[name]=i
            }
            have_header=1
            next
        }
        in_summary && have_header && $1 ~ /^[0-9]+([.][0-9]+)?$/ {
            split("score line cond toggle fsm branch group", metrics, " ")
            for (i=1; i<=7; i++) {
                name=metrics[i]
                if (column[name] > 0 && $(column[name]) ~ /^[0-9]+([.][0-9]+)?$/)
                    printf "%s|%s\n", name, $(column[name])
            }
            found=1
            exit
        }
        END {if (!found) exit 1}
        ' "$dashboard" > "$output"
    elif [[ -f "$report_dir/dashboard.html" ]]; then
        dashboard="$report_dir/dashboard.html"
        sed -e 's/&nbsp;/ /g' -e 's/<[^>]*>/\n/g' "$dashboard" | awk '
        function trim(value) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            return value
        }
        BEGIN {
            known["score"]=1; known["line"]=1; known["cond"]=1; known["toggle"]=1
            known["tgl"]=1; known["fsm"]=1; known["branch"]=1; known["assert"]=1; known["group"]=1
        }
        {
            token=trim($0)
            if (token=="") next
            if (token=="Total Coverage Summary") {in_summary=1; next}
            if (!in_summary) next
            name=tolower(token)
            if (!have_header && name=="score") {
                header[++columns]="score"
                have_header=1
                next
            }
            if (have_header && !have_values && known[name]) {
                if (name=="tgl") name="toggle"
                header[++columns]=name
                next
            }
            if (have_header && token ~ /^[0-9]+([.][0-9]+)?$/) {
                have_values=1
                value[++values]=token
                if (values==columns) {
                    for (i=1; i<=columns; i++)
                        if (header[i] != "assert") printf "%s|%s\n", header[i], value[i]
                    found=1
                    exit
                }
            }
        }
        END {if (!found) exit 1}
        ' > "$output"
    else
        return 1
    fi
    [[ -s "$output" ]]
}

runner_coverage_runtime_error_summary() {
    local manifest="$1" source seed_log sva_errors scoreboard_failed
    local sva_error_total=0 error_total=0
    declare -A seen_sources=() seen_logs=()
    [[ -f "$manifest" ]] || { printf '0|0\n'; return; }
    while IFS='|' read -r _ source _ _; do
        [[ "$source" == */seeds.latest.tsv && -f "$source" ]] || continue
        [[ -z "${seen_sources[$source]:-}" ]] || continue
        seen_sources[$source]=1
        while IFS='|' read -r _ _ _ _ _ _ seed_log _ _ _ sva_errors scoreboard_failed _ _; do
            [[ -f "$seed_log" && -z "${seen_logs[$seed_log]:-}" ]] || continue
            seen_logs[$seed_log]=1
            sva_error_total=$((sva_error_total + $(runner_log_metric_count "$seed_log" SVA_ERROR)))
            error_total=$((error_total + $(runner_log_metric_count "$seed_log" ERROR_TOTAL)))
        done < "$source"
    done < <(tail -n +2 "$manifest")
    printf '%s|%s\n' "$sva_error_total" "$error_total"
}

runner_runtime_scope_error_summary() {
    local scope="$1" log_file clean_log sva_error_total=0 error_total=0
    [[ -d "$scope" ]] || { printf '0|0\n'; return; }
    while IFS= read -r -d '' log_file; do
        if [[ "$log_file" == */sim.log ]]; then
            clean_log="${log_file%/sim.log}/sim.clean.log"
            [[ ! -f "$clean_log" ]] || continue
        fi
        sva_error_total=$((sva_error_total + $(runner_log_metric_count "$log_file" SVA_ERROR)))
        error_total=$((error_total + $(runner_log_metric_count "$log_file" ERROR_TOTAL)))
    done < <(find "$scope" -type f \( -path '*/logs/sim.clean.log' -o -path '*/logs/sim.log' \) -print0 2>/dev/null)
    printf '%s|%s\n' "$sva_error_total" "$error_total"
}

runner_report_regression() {
    local run_id="$1" run_dir="$2" manifest_file="$3" status_file="$4" start_epoch="$5" include_warnings="${6:-0}" case_status_file="${7:-}"
    local summary_dir latest_file case_latest_file summary_file errors_file quick_links_file
    local total passed failed retried status now duration burst test_name seeds attempt result rc reason attempt_dir index=0 log_file
    local tests case_total case_passed case_failed case_retried case_index=0 timestamp burst_attempt seed seed_attempt case_duration
    local warnings errors fatals sva_errors scoreboard_failed row_error
    local total_w=0 total_e=0 total_f=0 total_sva=0 total_error=0
    summary_dir="$run_dir/summary"
    latest_file="$summary_dir/regression.latest.tsv"
    case_latest_file="$summary_dir/regression.cases.latest.tsv"
    summary_file="$summary_dir/regression.log"
    errors_file="$summary_dir/regression.errors.log"
    quick_links_file="$summary_dir/failure_quick_links.log"
    mkdir -p "$summary_dir"
    awk -F'|' 'FNR==NR {if(FNR>1){order[++n]=$1; test[$1]=$2; seeds[$1]=$4} next} FNR>1 {attempt[$2]=$3; status[$2]=$4; rc[$2]=$5; reason[$2]=$6; dir[$2]=$7} END {for(i=1;i<=n;i++){b=order[i]; print b"|"test[b]"|"seeds[b]"|"attempt[b]"|"status[b]"|"rc[b]"|"reason[b]"|"dir[b]}}' \
        "$manifest_file" "$status_file" > "$latest_file"
    total="$(wc -l < "$latest_file" | tr -d '[:space:]')"
    passed="$(awk -F'|' '$5=="PASS" {n++} END {print n+0}' "$latest_file")"
    retried="$(awk -F'|' '$5=="PASS" && $4!="A001" {n++} END {print n+0}' "$latest_file")"
    failed=$((total - passed)); status=PASS; ((failed == 0)) || status=FAIL
    if [[ -n "$case_status_file" && -r "$case_status_file" ]]; then
        awk -F'|' 'NR>1 {key=$2 SUBSEP $5; if(!seen[key]++) order[++n]=key; row[key]=$0} END {for(i=1;i<=n;i++) print row[order[i]]}' \
            "$case_status_file" > "$case_latest_file"
    else
        : > "$case_latest_file"
    fi
    case_total="$(wc -l < "$case_latest_file" | tr -d '[:space:]')"
    tests="$(awk -F'|' '{seen[$4]=1} END {for(test in seen) if(test!="") n++; print n+0}' "$case_latest_file")"
    ((tests > 0)) || tests="$(awk -F'|' 'NR>1 {n++} END {print n+0}' "$manifest_file")"
    case_passed="$(awk -F'|' '$7=="PASS" {n++} END {print n+0}' "$case_latest_file")"
    case_failed=$((case_total - case_passed))
    case_retried="$(awk -F'|' '$7=="PASS" && ($3!="A001" || $6!="A001") {n++} END {print n+0}' "$case_latest_file")"
    while IFS='|' read -r timestamp burst burst_attempt test_name seed seed_attempt result rc reason case_duration log_file warnings errors fatals sva_errors scoreboard_failed; do
        total_w=$((total_w + ${warnings:-0}))
        total_e=$((total_e + ${errors:-0}))
        total_f=$((total_f + ${fatals:-0}))
        total_sva=$((total_sva + ${sva_errors:-0}))
        row_error="$(runner_log_metric_count "$log_file" ERROR_TOTAL)"
        total_error=$((total_error + row_error))
    done < "$case_latest_file"
    now="$(date +%s)"; duration="$(runner_report_duration "$((now - start_epoch))")"
    {
        printf '================================================================================\nRegression Summary\n'
        printf 'Run ID       : %s\nStatus       : %s\nTotal Tests  : %s\nTotal Cases  : %s\nPassed       : %s\nPass Retry   : %s\nFailed       : %s\n' \
            "$run_id" "$status" "$tests" "$case_total" "$case_passed" "$case_retried" "$case_failed"
        printf 'Total Bursts : %s\nBurst Passed : %s\nBurst Retry  : %s\nBurst Failed : %s\nDuration     : %s\n' \
            "$total" "$passed" "$retried" "$failed" "$duration"
        printf 'UVM Warning/Error/Fatal : %s/%s/%s\n' "$total_w" "$total_e" "$total_f"
        printf 'SVA Error    : %s\n' "$total_sva"
        printf 'Error Total  : %s\n' "$total_error"
        printf 'Manifest     : %s\nStatus DB    : %s\nCase DB      : %s\n' "$(runner_report_path "$manifest_file")" \
            "$(runner_report_path "$status_file")" "$(runner_report_path "$case_status_file")"
        printf '%s\n' '--------------------------------------------------------------------------------'
        while IFS='|' read -r timestamp burst burst_attempt test_name seed seed_attempt result rc reason case_duration log_file warnings errors fatals sva_errors scoreboard_failed; do
            case_index=$((case_index + 1))
            printf '[CASE-RESULT %s/%s]\n' "$case_index" "$case_total"
            printf 'Status       : %s\nBurst        : %s\nTest         : %s\nSeed         : %s\nBurst Attempt: %s\nSeed Attempt : %s\n' \
                "$result" "$burst" "$test_name" "$seed" "$burst_attempt" "$seed_attempt"
            printf 'RC           : %s\nReason       : %s\nTime         : %s\nDetail Log   : %s\n' \
                "$rc" "$reason" "$(runner_report_duration "${case_duration:-0}")" "$(runner_report_path "$log_file")"
            row_error="$(runner_log_metric_count "$log_file" ERROR_TOTAL)"
            printf 'UVM W/E/F    : %s/%s/%s\nSVA Error    : %s\nError Total  : %s\n' \
                "${warnings:-0}" "${errors:-0}" "${fatals:-0}" "${sva_errors:-0}" "$row_error"
            printf '%s\n' '--------------------------------------------------------------------------------'
        done < "$case_latest_file"
        printf 'Burst Results:\n'
        while IFS='|' read -r burst test_name seeds attempt result rc reason attempt_dir; do
            index=$((index + 1))
            printf '[TEST-RESULT %s/%s]\n' "$index" "$total"
            printf 'Status       : %s\nBurst        : %s\nTest         : %s\nSeeds        : %s\nAttempt      : %s\nRC           : %s\nReason       : %s\nAttempt Dir  : %s\n' \
                "${result:-NOT_RUN}" "$burst" "$test_name" "$seeds" "${attempt:--}" "${rc:--}" "${reason:--}" "$(runner_report_path "$attempt_dir")"
            printf '%s\n' '--------------------------------------------------------------------------------'
        done < "$latest_file"
        printf 'Attempt History:\n'; cat "$status_file"
        printf 'Completed    : %s\n================================================================================\n' "$(date -Is)"
    } > "$summary_file"
    : > "$errors_file"
    while IFS='|' read -r burst test_name seeds attempt result rc reason attempt_dir; do
        [[ "$result" == FAIL ]] || continue
        {
            printf '================================================================================\nBURST=%s TEST=%s ATTEMPT=%s RC=%s REASON=%s\n' "$burst" "$test_name" "$attempt" "$rc" "$reason"
            printf 'ATTEMPT_DIR=%s\n--------------------------------------------------------------------------------\n' "$(runner_report_path "$attempt_dir")"
        } >> "$errors_file"
        while IFS= read -r -d '' log_file; do
            { printf 'FILE=%s\n' "$(runner_report_path "$log_file")"; runner_report_extract_failures "$log_file" "$include_warnings"; } >> "$errors_file"
        done < <(find "$attempt_dir" -type f -name '*.log' -print0 2>/dev/null)
    done < "$latest_file"
    [[ -s "$errors_file" ]] || rm -f "$errors_file"
    : > "$quick_links_file"
    case_index=0
    while IFS='|' read -r timestamp burst burst_attempt test_name seed seed_attempt result rc reason case_duration log_file warnings errors fatals sva_errors scoreboard_failed; do
        [[ "$result" == FAIL ]] || continue
        case_index=$((case_index + 1))
        runner_report_failure_link "$case_index" "$burst" "$burst_attempt" "$test_name" "$seed" "$rc" "$reason" "$log_file" \
            >> "$quick_links_file"
    done < "$case_latest_file"
    if [[ -s "$quick_links_file" ]]; then
        {
            printf '%s\nFailure Quick Links\n%s\n' '--------------------------------------------------------------------------------' '--------------------------------------------------------------------------------'
            cat "$quick_links_file"
        } >> "$summary_file"
    else
        rm -f "$quick_links_file"
    fi
    runner_write_artifact_index "$run_dir"
    runner_report_terminal_dashboard "Regression Summary" "$status" "$case_total" "$case_passed" "$case_failed" "$duration" "$summary_file" "$([[ -f "$errors_file" ]] && printf '%s' "$errors_file")"
    if [[ "${RUNNER_REPORT_QUIET:-0}" != 1 && -f "$quick_links_file" ]]; then
        printf '\nFailure Quick Links\n%s\n' '--------------------------------------------------------------------------------'
        cat "$quick_links_file"
    fi
}

runner_report_coverage() {
    local output_dir="$1" status="$2" metric="${3:-}" value="${4:-}" target="${5:-}"
    local runtime_scope="${6:-}"
    local report_dir summary_file dashboard='' metrics_file metric_name metric_value
    local runtime_summary sva_errors=0 error_total=0
    report_dir="$output_dir/report"
    summary_file="$output_dir/coverage.log"
    [[ -f "$report_dir/dashboard.html" ]] && dashboard="$report_dir/dashboard.html"
    [[ -n "$dashboard" ]] || { [[ -f "$report_dir/dashboard.txt" ]] && dashboard="$report_dir/dashboard.txt"; }
    metrics_file="$output_dir/coverage_metrics.tsv"
    runner_coverage_parse_metrics "$report_dir" "$metrics_file" 2>/dev/null || rm -f "$metrics_file"
    if [[ -n "$runtime_scope" ]]; then
        runtime_summary="$(runner_runtime_scope_error_summary "$runtime_scope")"
    else
        runtime_summary="$(runner_coverage_runtime_error_summary "$output_dir/vdb_manifest.tsv")"
    fi
    IFS='|' read -r sva_errors error_total <<< "$runtime_summary"
    {
        printf '================================================================================\nCoverage Summary\n'
        printf 'Status       : %s\nMetric       : %s\nValue        : %s\nTarget       : %s\n' "$status" "${metric:--}" "${value:--}" "${target:--}"
        printf 'SVA Error    : %s\nError Total  : %s\n' "$sva_errors" "$error_total"
        printf 'Report Dir   : %s\nDashboard    : %s\n' "$(runner_report_path "$report_dir")" "$([[ -n "$dashboard" ]] && runner_report_path "$dashboard" || printf '%s' 'not generated')"
        if [[ -f "$metrics_file" ]]; then
            printf '%s\n' '--------------------------------------------------------------------------------'
            while IFS='|' read -r metric_name metric_value; do printf '%-12s : %s%%\n' "${metric_name^^}" "$metric_value"; done < "$metrics_file"
        fi
        printf '================================================================================\n'
    } > "$summary_file"
    runner_write_artifact_index "$output_dir" "$output_dir/artifacts.tsv"
    if [[ "${RUNNER_REPORT_QUIET:-0}" != 1 ]]; then
        printf '\n================================================================================\n  Coverage Summary\n================================================================================\n'
        printf ' Status       : %s\n Metric       : %s\n Value        : %s\n Target       : %s\n' "$status" "${metric:--}" "${value:--}" "${target:--}"
        printf ' SVA Error    : %s\n Error Total  : %s\n' "$sva_errors" "$error_total"
        printf ' Summary Log  : %s\n' "$(runner_report_path "$summary_file")"
        [[ -z "$dashboard" ]] || printf ' Dashboard    : file://%s\n' "$dashboard"
        if [[ -f "$metrics_file" ]]; then
            while IFS='|' read -r metric_name metric_value; do printf ' %-12s : %s%%\n' "${metric_name^^}" "$metric_value"; done < "$metrics_file"
        fi
        printf '================================================================================\n'
    fi
}
