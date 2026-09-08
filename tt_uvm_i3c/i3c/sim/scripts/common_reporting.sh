#!/usr/bin/env bash

runner_report_path() {
    local path="$1" report_root="${RUNNER_REPORT_ROOT:-$RUNNER_ROOT}"
    if [[ "$path" == "$report_root/"* ]]; then printf '%s\n' "${path#"$report_root/"}"
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
            if runner_log_has_unwaived_match "$file" "${RUNNER_SVA_MARKER_REGEX:-SVA:[[:space:]]*[[:alnum:]_.$:/-]+}"; then
                value="$(grep -Eiv "${RUNNER_SVA_WAIVER_REGEX:-SVA_WAIVED|\[WAIVED\]}" "$file" 2>/dev/null | grep -Eic "${RUNNER_SVA_MARKER_REGEX:-SVA:[[:space:]]*[[:alnum:]_.$:/-]+}" || true)"
            else
                value="$(grep -Eiv "${RUNNER_SVA_WAIVER_REGEX:-SVA_WAIVED|\[WAIVED\]}" "$file" 2>/dev/null | grep -Eic "${RUNNER_SVA_FAILURE_REGEX:-Assertion.*(fail|error)|assertion[[:space:]_-]*failed}" || true)"
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
    if runner_log_has_unwaived_match "$log_file" "${RUNNER_SVA_MARKER_REGEX:-SVA:[[:space:]]*[[:alnum:]_.$:/-]+}"; then
        assertion_pattern="${RUNNER_SVA_MARKER_REGEX:-SVA:[[:space:]]*[[:alnum:]_.$:/-]+}"
    fi
    pattern="${RUNNER_UVM_FAILURE_REGEX}|${RUNNER_PLAIN_ERROR_REGEX}|${assertion_pattern}|${RUNNER_SCOREBOARD_FAILURE_REGEX}|TEST[[:space:]_-]*FAIL|Fatal License Error|Cannot connect to the license server|SCL-[0-9]+|Segmentation fault|Internal error|syntax error"
    ((include_warnings)) && pattern="${pattern}|UVM_WARNING[[:space:]]*:[[:space:]]*[1-9]|^[[:space:]]*Warning:"
    grep -Ein "$pattern" "$log_file" 2>/dev/null | grep -Eiv "${RUNNER_SVA_WAIVER_REGEX:-SVA_WAIVED|\[WAIVED\]}" | tail -n 80 || true
}

runner_report_assertion_failures() {
    local log_file="$1" pattern
    log_file="$(runner_log_for_analysis "$log_file")"
    [[ -f "$log_file" ]] || return 0
    pattern="${RUNNER_SVA_MARKER_REGEX:-SVA:[[:space:]]*[[:alnum:]_.$:/-]+}"
    if ! runner_log_has_unwaived_match "$log_file" "$pattern"; then
        pattern="${RUNNER_SVA_FAILURE_REGEX:-Assertion.*(fail|error)|assertion[[:space:]_-]*failed}"
    fi
    grep -Ein "$pattern" "$log_file" 2>/dev/null | grep -Eiv "${RUNNER_SVA_WAIVER_REGEX:-SVA_WAIVED|\[WAIVED\]}" | tail -n 80 || true
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
    local root="$1" output="${2:-$1/summary/artifacts.tsv}" path bytes modified kind
    [[ -d "$root" ]] || return 0
    mkdir -p "$(dirname "$output")"
    printf 'kind|path|bytes|modified\n' > "$output"
    while IFS= read -r -d '' path &&
          IFS= read -r -d '' bytes &&
          IFS= read -r -d '' modified; do
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
        printf '%s|%s|%s|%s\n' "$kind" "$path" "${bytes:-0}" \
            "${modified:-unknown}" >> "$output"
    # Coverage databases may contain tens of thousands of implementation
    # files.  Index the database directory as one artifact below, but never
    # descend into it: those internal files are not user-facing artifacts and
    # walking/statting each one can delay command completion for minutes.
    # GNU find emits path, size, and timestamp in one traversal. This avoids
    # launching wc and date once per artifact, which was especially costly on
    # shared filesystems after a large regression.
    done < <(find "$root" -type d -name '*.vdb' -prune -o \
        -type f ! -path "$output" \
        -printf '%p\0%s\0%TY-%Tm-%TdT%TH:%TM:%TS%Tz\0' 2>/dev/null)
    while IFS= read -r -d '' path &&
          IFS= read -r -d '' modified; do
        printf 'coverage_db|%s|0|%s\n' "$path" \
            "${modified:-unknown}" >> "$output"
    done < <(find "$root" -type d -name '*.vdb' \
        -printf '%p\0%TY-%Tm-%TdT%TH:%TM:%TS%Tz\0' -prune 2>/dev/null)
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
    runner_publish_html_summary "$run_dir"
    runner_write_artifact_index "$run_dir"
    runner_report_terminal_dashboard "Compile Summary" "$status" 1 "$((rc == 0 ? 1 : 0))" "$((rc == 0 ? 0 : 1))" "$duration" "$summary_file" "$([[ -f "$errors_file" ]] && printf '%s' "$errors_file")"
    if [[ "${RUNNER_REPORT_QUIET:-0}" != 1 ]]; then
        if ((rc == 0)); then runner_status_token PASS; printf ' COMPILE project=%s run=%s\n' "${DV_PROJECT_NAME:-unknown}" "$run_id"
        else runner_status_token FAIL; printf ' COMPILE project=%s run=%s rc=%s log=%s\n' "${DV_PROJECT_NAME:-unknown}" "$run_id" "$rc" "$(runner_report_path "$log_file")"
        fi
    fi
}

runner_report_compile_log_path() {
    local attempt_dir="$1"
    local compile_log="$attempt_dir/compile_logs/compile.log"
    [[ -f "$compile_log" ]] || compile_log="$attempt_dir/logs/compile/compile.log"
    if [[ -f "$compile_log" ]]; then runner_report_path "$compile_log"; else printf '%s\n' '-'; fi
}

runner_report_dump_format() {
    local status="${1:-DISABLED}" dump_file="${2:-}" fallback="${3:-none}"
    if [[ "$status" == DISABLED || -z "$dump_file" ]]; then printf '%s\n' "$fallback"
    elif [[ "$dump_file" == *.* ]]; then printf '%s\n' "${dump_file##*.}"
    else printf '%s\n' unknown
    fi
}

runner_html_escape() {
    local value="${1:-}" restore_patsub=0
    # Bash 5.1 (still common on VCS hosts) does not know the optional
    # patsub_replacement setting introduced later.  Probe quietly so report
    # generation never turns an otherwise useful diagnostic into shell noise.
    if shopt -q patsub_replacement 2>/dev/null; then
        restore_patsub=1
        shopt -u patsub_replacement
    fi
    value="${value//&/&amp;}"; value="${value//</&lt;}"; value="${value//>/&gt;}"
    value="${value//\"/&quot;}"; value="${value//\'/&#39;}"
    ((restore_patsub == 0)) || shopt -s patsub_replacement
    printf '%s' "$value"
}

runner_html_link() {
    local summary_dir="$1" target="${2:-}" label="${3:-Open}" relative
    if [[ -z "$target" || ! -e "$target" ]]; then printf '%s' '-'; return 0; fi
    relative="$(realpath -m --relative-to="$summary_dir" "$target" 2>/dev/null)" || { printf '%s' '-'; return 0; }
    printf '<a href="%s">%s</a>' "$(runner_html_escape "$relative")" "$(runner_html_escape "$label")"
}

runner_html_case_row() {
    local output="$1" summary_dir="$2" status="$3" test_name="$4" case_id="$5" seed="$6"
    local iteration="$7" burst="$8" warnings="$9" errors="${10}" fatals="${11}" sva_errors="${12}"
    local error_total="${13}" dump_format="${14}" dump_file="${15}" compile_log="${16}" detail_log="${17}"
    {
        printf '<tr data-status="%s"><td class="status %s">%s</td>' \
            "$(runner_html_escape "$status")" "$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')" "$(runner_html_escape "$status")"
        printf '<td>%s</td><td>%s</td><td>%s</td><td class="iteration">%s</td><td class="burst">%s</td>' \
            "$(runner_html_escape "$test_name")" "$(runner_html_escape "${case_id:-default}")" \
            "$(runner_html_escape "$seed")" "$(runner_html_escape "${iteration:--}")" "$(runner_html_escape "${burst:--}")"
        printf '<td>%s/%s/%s</td><td>%s</td><td>%s</td><td>%s</td><td>' \
            "${warnings:-0}" "${errors:-0}" "${fatals:-0}" "${sva_errors:-0}" "${error_total:-0}" \
            "$(runner_html_escape "${dump_format:-none}")"
        runner_html_link "$summary_dir" "$dump_file" Dump
        printf '</td><td>'; runner_html_link "$summary_dir" "$compile_log" Compile
        printf '</td><td>'; runner_html_link "$summary_dir" "$detail_log" Detail
        printf '</td></tr>\n'
    } >> "$output"
}

runner_write_html_summary() {
    local run_dir="$1" summary_dir="$1/summary" output="$1/summary/run_summary.html"
    local tmp="$1/summary/.run_summary.html.tmp.$$" run_id run_type=unknown main_summary='' status=UNKNOWN
    local case_file seed_file iteration_dir timestamp burst burst_attempt test_name case_id level plusargs seed seed_attempt result rc reason case_duration log_file
    local warnings errors fatals sva_errors scoreboard_failed error_total dump_status dump_format dump_file attempt_number compile_log
    [[ -d "$run_dir" ]] || return 1
    mkdir -p "$summary_dir"
    run_id="$(basename "$run_dir")"
    if [[ -r "$summary_dir/regression.log" && -d "$run_dir/iterations" ]]; then run_type=coverage; main_summary="$summary_dir/regression.log"
    elif [[ -r "$summary_dir/regression.log" ]]; then run_type=regression; main_summary="$summary_dir/regression.log"
    elif [[ -r "$summary_dir/test.log" ]]; then run_type=test; main_summary="$summary_dir/test.log"
    elif [[ -r "$summary_dir/compile.log" ]]; then run_type=compile; main_summary="$summary_dir/compile.log"
    fi
    if [[ -r "$main_summary" ]]; then
        status="$(awk '/^[[:space:]]*Status[[:space:]]*:/ {sub(/^[^:]*:[[:space:]]*/, ""); print; exit}' "$main_summary")"
    fi
    [[ -n "$status" ]] || status=UNKNOWN
    {
        printf '%s\n' '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        printf '<meta name="viewport" content="width=device-width,initial-scale=1"><title>%s</title>\n' "$(runner_html_escape "$run_id summary")"
        printf '%s\n' '<style>body{font:14px system-ui,sans-serif;margin:24px;color:#1f2937}h1{margin-bottom:4px}.meta{color:#4b5563;margin-bottom:8px}.tools{display:flex;gap:10px;margin:14px 0}input,select{padding:7px}table{border-collapse:collapse;width:100%}th,td{border:1px solid #d1d5db;padding:7px;text-align:left}th{background:#f3f4f6;position:sticky;top:0}.status{font-weight:700}.pass{color:#087f23}.fail{color:#b42318}a{color:#075985}code{background:#f3f4f6;padding:2px 4px}.type-test .iteration,.type-test .burst,.type-compile .iteration,.type-compile .burst{display:none}</style></head>'
        printf '<body class="type-%s"><h1>Run Summary</h1><div class="meta">Run ID: <code>%s</code> · Type: %s · Status: <span class="status %s">%s</span> · <span id="counts">0 cases</span></div>\n' \
            "$(runner_html_escape "$run_type")" \
            "$(runner_html_escape "$run_id")" "$(runner_html_escape "$run_type")" \
            "$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')" "$(runner_html_escape "$status")"
        printf '<div>Text report: '; runner_html_link "$summary_dir" "$main_summary" Open; printf '</div>\n'
        printf '%s\n' '<div class="tools"><input id="query" placeholder="Filter test or case"><select id="verdict"><option value="">All status</option><option>FAIL</option><option>PASS</option></select></div>'
        printf '%s\n' '<table><thead><tr><th>Status</th><th>Test</th><th>Case</th><th>Seed</th><th class="iteration">Iteration</th><th class="burst">Burst</th><th>UVM W/E/F</th><th>SVA</th><th>Errors</th><th>Format</th><th>Dump</th><th>Compile</th><th>Detail</th></tr></thead><tbody>'
    } > "$tmp"

    if [[ "$run_type" == coverage ]]; then
        while IFS= read -r case_file; do
            iteration_dir="$(dirname "$(dirname "$case_file")")"
            while IFS='|' read -r timestamp burst burst_attempt test_name case_id level plusargs seed seed_attempt result rc reason case_duration log_file warnings errors fatals sva_errors scoreboard_failed error_total dump_status dump_format dump_file; do
                [[ "$case_id" == "$test_name" ]] && case_id=default
                attempt_number="${burst_attempt#A}"; compile_log="$iteration_dir/bursts/$burst/attempt_$attempt_number/compile_logs/compile.log"
                runner_html_case_row "$tmp" "$summary_dir" "$result" "$test_name" "$case_id" "$seed" \
                    "$(basename "$iteration_dir")" "$burst" "$warnings" "$errors" "$fatals" "$sva_errors" "$error_total" \
                    "${dump_format:-none}" "$dump_file" "$compile_log" "$log_file"
            done < "$case_file"
        done < <(find "$run_dir/iterations" -type f -path '*/summary/regression.cases.latest.tsv' | sort)
    elif [[ "$run_type" == regression ]]; then
        case_file="$summary_dir/regression.cases.latest.tsv"
        if [[ -r "$case_file" ]]; then
            while IFS='|' read -r timestamp burst burst_attempt test_name case_id level plusargs seed seed_attempt result rc reason case_duration log_file warnings errors fatals sva_errors scoreboard_failed error_total dump_status dump_format dump_file; do
                [[ "$case_id" == "$test_name" ]] && case_id=default
                attempt_number="${burst_attempt#A}"; compile_log="$run_dir/bursts/$burst/attempt_$attempt_number/compile_logs/compile.log"
                runner_html_case_row "$tmp" "$summary_dir" "$result" "$test_name" "$case_id" "$seed" - "$burst" \
                    "$warnings" "$errors" "$fatals" "$sva_errors" "$error_total" "${dump_format:-none}" "$dump_file" "$compile_log" "$log_file"
            done < "$case_file"
        fi
    elif [[ "$run_type" == test ]]; then
        seed_file="$summary_dir/seeds.latest.tsv"; compile_log="$run_dir/compile_logs/compile.log"
        if [[ -r "$seed_file" ]]; then
            while IFS='|' read -r seed seed_attempt result rc reason case_duration log_file warnings errors fatals sva_errors scoreboard_failed dump_status dump_file; do
                error_total="$(runner_log_metric_count "$log_file" ERROR_TOTAL)"
                dump_format="$(runner_report_dump_format "${dump_status:-DISABLED}" "$dump_file" none)"
                runner_html_case_row "$tmp" "$summary_dir" "$result" "${TEST_NAME:-$(awk '/^Test[[:space:]]*:/ {print $3; exit}' "$main_summary")}" default "$seed" - - \
                    "$warnings" "$errors" "$fatals" "$sva_errors" "$error_total" "$dump_format" "$dump_file" "$compile_log" "$log_file"
            done < "$seed_file"
        fi
    elif [[ "$run_type" == compile ]]; then
        compile_log="$run_dir/compile_logs/compile.log"
        runner_html_case_row "$tmp" "$summary_dir" "$status" compile default - - - 0 0 0 0 0 none '' "$compile_log" ''
    fi
    {
        printf '%s\n' '</tbody></table>'
        printf '%s\n' '<script>const q=document.getElementById("query"),v=document.getElementById("verdict"),b=document.querySelector("tbody"),rows=[...b.rows];rows.sort((a,z)=>(a.dataset.status==="FAIL"?0:1)-(z.dataset.status==="FAIL"?0:1)).forEach(r=>b.appendChild(r));const pass=rows.filter(r=>r.dataset.status==="PASS").length,fail=rows.filter(r=>r.dataset.status==="FAIL").length;document.getElementById("counts").textContent=`${rows.length} cases · ${pass} pass · ${fail} fail`;function f(){rows.forEach(r=>r.hidden=((!!v.value&&r.dataset.status!==v.value)||!r.textContent.toLowerCase().includes(q.value.toLowerCase())))}q.oninput=f;v.onchange=f;</script>'
        printf '%s\n' '</body></html>'
    } >> "$tmp"
    mv -f "$tmp" "$output"
}

runner_publish_html_summary() {
    local run_dir="$1"
    runner_write_html_summary "$run_dir" || { rm -f "$run_dir/summary/.run_summary.html.tmp."* 2>/dev/null || true; runner_warn "Unable to generate HTML summary: $run_dir"; return 0; }
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
    local level_code="${9:--}" case_display="${10:--}"
    [[ "$burst" == B* ]] || burst="$(printf 'B%03d' "${burst:-1}")"
    [[ "$attempt" == A* ]] || attempt="$(printf 'A%03d' "${attempt:-1}")"
    if [[ "$status" == PASS ]]; then
        runner_status_token PASS
        printf '  %s %s %s S=%-10s T=%-60s C=%s\n' \
            "$burst" "$attempt" "$level_code" "$seed" "$test_name" "$case_display"
    else
        runner_status_token FAIL
        printf '  %s %s %s S=%-10s T=%-60s C=%s\n' \
            "$burst" "$attempt" "$level_code" "$seed" "$test_name" "$case_display"
        printf '       reasons=[%s]\n' "$(runner_failure_causes "$rc" "$reason" "$log_file")"
        printf '       log=%s\n' "$(runner_report_path "$log_file")"
    fi
}

runner_report_failure_link() {
    local index="$1" burst="$2" attempt="$3" test_name="$4" seed="$5" rc="$6" reason="$7" log_file="$8"
    local case_id="${9:-default}" level="${10:--}" plusargs="${11:-none}"
    [[ "$burst" == B* ]] || burst="$(printf 'B%03d' "${burst:-1}")"
    [[ "$attempt" == A* ]] || attempt="$(printf 'A%03d' "${attempt:-1}")"
    [[ "$case_id" == "$test_name" ]] && case_id=default
    printf '[FAILURE %s]\n' "$index"
    printf '  Burst    : %s\n  Attempt  : %s\n  Level    : %s\n  Seed     : %s\n' "$burst" "$attempt" "$level" "$seed"
    printf '  Test     : %s\n  Case     : %s\n  Plusargs : %s\n' "$test_name" "${case_id:-default}" "${plusargs:-none}"
    printf '  Reason   : %s\n' "$(runner_failure_causes "$rc" "$reason" "$log_file")"
    printf '  Log      : %s\n' "$(runner_report_path "$log_file")"
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
    local summary_dir latest_file summary_file errors_file quick_links_file error_totals_file
    local total passed failed status now duration seed attempt result rc reason elapsed log_file index=0
    local warnings errors fatals sva_errors scoreboard_failed dump_status dump_file row_error total_w=0 total_e=0 total_f=0 total_sva=0 total_error=0 retried=0 missing_dumps=0
    local -A seed_error_total=()
    summary_dir="$run_dir/summary"
    latest_file="$summary_dir/seeds.latest.tsv"
    summary_file="$summary_dir/test.log"
    errors_file="$summary_dir/test.errors.log"
    quick_links_file="$summary_dir/failure_quick_links.log"
    error_totals_file="$summary_dir/error_totals.tsv"
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
            seed_error_total["$seed|$attempt"]="$row_error"
            total_error=$((total_error + row_error))
            [[ "$dump_status" != MISSING ]] || missing_dumps=$((missing_dumps + 1))
            # "Pass after retry": only a non-first attempt that actually PASSED,
            # matching the regression metric (see runner_report_regression's
            # $result==PASS && attempt!=A001 rule). Without the PASS guard this
            # counted every retry, so a failing test wrongly showed retried>0.
            [[ "${attempt#A}" == 001 || "$result" != PASS ]] || retried=$((retried + 1))
        done < "$latest_file"
        printf 'seed|attempt|error_total\n' > "$error_totals_file"
        for seed in "${!seed_error_total[@]}"; do
            printf '%s|%s\n' "$seed" "${seed_error_total[$seed]}" >> "$error_totals_file"
        done
        printf 'Pass After Retry : %s\n' "$retried"
        printf 'UVM Warning/Error/Fatal : %s/%s/%s\n' "$total_w" "$total_e" "$total_f"
        printf 'SVA Error    : %s\n' "$total_sva"
        printf 'Error Total  : %s\n' "$total_error"
        printf 'Missing Dumps : %s\n' "$missing_dumps"
        printf 'Duration     : %s\n' "$duration"
        printf '%s\n' '--------------------------------------------------------------------------------'
        while IFS='|' read -r seed attempt result rc reason elapsed log_file warnings errors fatals sva_errors scoreboard_failed dump_status dump_file; do
            index=$((index + 1))
            printf '[CASE-RESULT %s/%s]\n' "$index" "$total"
            printf 'Status       : %s\nTest         : %s\nCase         : default\nLevel        : direct\n' "$result" "$test_name"
            printf 'Plusargs     : %s\nSeed         : %s\nRC           : %s\nReason       : %s\nTime         : %s\n' \
                "${TEST_PLUSARGS:-none}" "$seed" "$rc" "$reason" "$(runner_report_duration "$elapsed")"
            row_error="${seed_error_total["$seed|$attempt"]:-}"
            [[ "$row_error" =~ ^[0-9]+$ ]] || row_error="$(runner_log_metric_count "$log_file" ERROR_TOTAL)"
            printf 'UVM W/E/F    : %s/%s/%s\nSVA Error    : %s\nError Total  : %s\n' \
                "${warnings:-0}" "${errors:-0}" "${fatals:-0}" "${sva_errors:-0}" "$row_error"
            printf 'Dump Status  : %s\nDump Format  : %s\nDump File    : %s\n' \
                "${dump_status:-DISABLED}" \
                "$(runner_report_dump_format "${dump_status:-DISABLED}" "$dump_file" "${TEST_DUMP_FORMAT:-none}")" \
                "$([[ -n "$dump_file" ]] && runner_report_path "$dump_file" || printf '%s' '-')"
            printf 'Compile Log  : %s\nDetail Log   : %s\n' \
                "$(runner_report_compile_log_path "$run_dir")" "$(runner_report_path "$log_file")"
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
    runner_publish_html_summary "$run_dir"
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
            split("score line cond toggle fsm branch assert group", metrics, " ")
            for (i=1; i<=8; i++) {
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
            upper=toupper(token)
            if (have_header && (token ~ /^[0-9]+([.][0-9]+)?$/ ||
                                upper=="N/A" || upper=="NA" || token=="--" || token=="-")) {
                have_values=1
                value[++values]=token
                if (values==columns) {
                    for (i=1; i<=columns; i++)
                        if (value[i] ~ /^[0-9]+([.][0-9]+)?$/)
                            printf "%s|%s\n", header[i], value[i]
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

runner_coverage_metric_rows() {
    local metrics_file="$1" prefix="${2:-}" metric value display
    for metric in score line cond toggle fsm branch assert group; do
        value=''
        if [[ -f "$metrics_file" ]]; then
            value="$(awk -F'|' -v metric="$metric" '$1==metric && $2 ~ /^[0-9]+([.][0-9]+)?$/ {print $2; exit}' "$metrics_file")"
        fi
        if [[ -n "$value" ]]; then display="${value}%"; else display='N/A'; fi
        printf '%s%-12s : %s\n' "$prefix" "${metric^^}" "$display"
    done
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
    local case_id level plusargs case_display
    local warnings errors fatals sva_errors scoreboard_failed row_error cached_error dump_status dump_format dump_file
    local error_case error_level error_plusargs
    local total_w=0 total_e=0 total_f=0 total_sva=0 total_error=0
    local -A cached_error_total=()
    summary_dir="$run_dir/summary"
    latest_file="$summary_dir/regression.latest.tsv"
    case_latest_file="$summary_dir/regression.cases.latest.tsv"
    summary_file="$summary_dir/regression.log"
    errors_file="$summary_dir/regression.errors.log"
    quick_links_file="$summary_dir/failure_quick_links.log"
    mkdir -p "$summary_dir"
    runner_report_progress_update case-summary
    awk -F'|' 'FNR==NR {if(FNR==1){v2=($3=="case_id"); next} order[++n]=$1; test[$1]=$2; seeds[$1]=$(v2?5:4); next} FNR>1 {attempt[$2]=$3; status[$2]=$4; rc[$2]=$5; reason[$2]=$6; dir[$2]=$7} END {for(i=1;i<=n;i++){b=order[i]; print b"|"test[b]"|"seeds[b]"|"attempt[b]"|"status[b]"|"rc[b]"|"reason[b]"|"dir[b]}}' \
        "$manifest_file" "$status_file" > "$latest_file"
    total="$(wc -l < "$latest_file" | tr -d '[:space:]')"
    passed="$(awk -F'|' '$5=="PASS" {n++} END {print n+0}' "$latest_file")"
    retried="$(awk -F'|' '$5=="PASS" && $4!="A001" {n++} END {print n+0}' "$latest_file")"
    failed=$((total - passed)); status=PASS; ((failed == 0)) || status=FAIL
    if [[ -n "$case_status_file" && -r "$case_status_file" ]]; then
        awk -F'|' 'NR>1 {key=$2 SUBSEP $8; if(!seen[key]++) order[++n]=key; row[key]=$0} END {for(i=1;i<=n;i++) print row[order[i]]}' \
            "$case_status_file" > "$case_latest_file"
    else
        : > "$case_latest_file"
    fi
    case_total="$(wc -l < "$case_latest_file" | tr -d '[:space:]')"
    tests="$(awk -F'|' '{seen[$4]=1} END {for(test in seen) if(test!="") n++; print n+0}' "$case_latest_file")"
    ((tests > 0)) || tests="$(awk -F'|' 'NR>1 {n++} END {print n+0}' "$manifest_file")"
    case_passed="$(awk -F'|' '$10=="PASS" {n++} END {print n+0}' "$case_latest_file")"
    case_failed=$((case_total - case_passed))
    case_retried="$(awk -F'|' '$10=="PASS" && ($3!="A001" || $9!="A001") {n++} END {print n+0}' "$case_latest_file")"
    runner_report_progress_update error-metrics
    while IFS='|' read -r timestamp burst burst_attempt test_name case_id level plusargs seed seed_attempt result rc reason case_duration log_file warnings errors fatals sva_errors scoreboard_failed row_error dump_status dump_format dump_file; do
        total_w=$((total_w + ${warnings:-0}))
        total_e=$((total_e + ${errors:-0}))
        total_f=$((total_f + ${fatals:-0}))
        total_sva=$((total_sva + ${sva_errors:-0}))
        [[ "$row_error" =~ ^[0-9]+$ ]] || row_error="$(runner_log_metric_count "$log_file" ERROR_TOTAL)"
        cached_error_total["$log_file"]="$row_error"
        total_error=$((total_error + row_error))
    done < "$case_latest_file"
    now="$(date +%s)"; duration="$(runner_report_duration "$((now - start_epoch))")"
    runner_report_progress_update summary
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
        while IFS='|' read -r timestamp burst burst_attempt test_name case_id level plusargs seed seed_attempt result rc reason case_duration log_file warnings errors fatals sva_errors scoreboard_failed row_error dump_status dump_format dump_file; do
            case_index=$((case_index + 1))
            case_display="$case_id"; [[ "$case_display" == "$test_name" ]] && case_display=default
            printf '[CASE-RESULT %s/%s]\n' "$case_index" "$case_total"
            printf 'Status       : %s\nBurst        : %s\nTest         : %s\nCase         : %s\n' \
                "$result" "$burst" "$test_name" "${case_display:-default}"
            printf 'Level        : %s\nPlusargs     : %s\nSeed         : %s\nBurst Attempt : %s\nSeed Attempt  : %s\n' \
                "$level" "${plusargs:-none}" "$seed" "$burst_attempt" "$seed_attempt"
            printf 'RC           : %s\nReason       : %s\nTime         : %s\n' \
                "$rc" "$reason" "$(runner_report_duration "${case_duration:-0}")"
            cached_error="${cached_error_total[$log_file]:-}"
            if [[ "$cached_error" =~ ^[0-9]+$ ]]; then row_error="$cached_error"
            elif [[ ! "$row_error" =~ ^[0-9]+$ ]]; then row_error="$(runner_log_metric_count "$log_file" ERROR_TOTAL)"
            fi
            printf 'UVM W/E/F    : %s/%s/%s\nSVA Error    : %s\nError Total  : %s\n' \
                "${warnings:-0}" "${errors:-0}" "${fatals:-0}" "${sva_errors:-0}" "$row_error"
            printf 'Dump Status  : %s\nDump Format  : %s\nDump File    : %s\n' \
                "${dump_status:-DISABLED}" "${dump_format:-none}" \
                "$([[ -n "$dump_file" ]] && runner_report_path "$dump_file" || printf '%s' '-')"
            local case_attempt_number="${burst_attempt#A}"
            printf 'Compile Log  : %s\nDetail Log   : %s\n' \
                "$(runner_report_compile_log_path "$run_dir/bursts/$burst/attempt_$case_attempt_number")" \
                "$(runner_report_path "$log_file")"
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
    runner_report_progress_update failure-extract
    : > "$errors_file"
    while IFS='|' read -r burst test_name seeds attempt result rc reason attempt_dir; do
        [[ "$result" == FAIL ]] || continue
        IFS='|' read -r error_case error_plusargs error_level < <(
            awk -F'|' -v b="$burst" '$1==b {print $3"|"$6"|"$7; exit}' "$manifest_file")
        [[ "$error_case" == "$test_name" ]] && error_case=default
        {
            printf '================================================================================\nRegression Failure\n'
            printf 'Result      : FAIL\nBurst       : %s\nAttempt     : %s\nLevel       : %s\n' "$burst" "$attempt" "${error_level:--}"
            printf 'Test        : %s\nCase        : %s\nPlusargs    : %s\n' "$test_name" "${error_case:-default}" "${error_plusargs:-none}"
            printf 'RC          : %s\nReason      : %s\nAttempt Dir : %s\n' "$rc" "$reason" "$(runner_report_path "$attempt_dir")"
            printf '%s\n' '--------------------------------------------------------------------------------'
        } >> "$errors_file"
        while IFS= read -r -d '' log_file; do
            { printf 'FILE=%s\n' "$(runner_report_path "$log_file")"; runner_report_extract_failures "$log_file" "$include_warnings"; } >> "$errors_file"
        done < <(find "$attempt_dir" -type f -name '*.log' -print0 2>/dev/null)
    done < "$latest_file"
    [[ -s "$errors_file" ]] || rm -f "$errors_file"
    runner_report_progress_update failure-links
    : > "$quick_links_file"
    case_index=0
    while IFS='|' read -r timestamp burst burst_attempt test_name case_id level plusargs seed seed_attempt result rc reason case_duration log_file warnings errors fatals sva_errors scoreboard_failed row_error dump_status dump_format dump_file; do
        [[ "$result" == FAIL ]] || continue
        case_index=$((case_index + 1))
        runner_report_failure_link "$case_index" "$burst" "$burst_attempt" "$test_name" "$seed" "$rc" "$reason" "$log_file" \
            "$case_id" "$level" "$plusargs" \
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
    runner_report_progress_update artifact-index
    runner_publish_html_summary "$run_dir"
    runner_write_artifact_index "$run_dir"
    runner_report_progress_update dashboard
    runner_report_terminal_dashboard "Regression Summary" "$status" "$case_total" "$case_passed" "$case_failed" "$duration" "$summary_file" "$([[ -f "$errors_file" ]] && printf '%s' "$errors_file")"
    if [[ "${RUNNER_REPORT_QUIET:-0}" != 1 && -f "$quick_links_file" ]]; then
        printf '\nFailure Quick Links\n%s\n' '--------------------------------------------------------------------------------'
        cat "$quick_links_file"
    fi
}

runner_report_coverage() {
    local output_dir="$1" status="$2" metric="${3:-}" value="${4:-}" target="${5:-}"
    local runtime_scope="${6:-}"
    local report_dir summary_file dashboard='' metrics_file
    local runtime_summary sva_errors=0 error_total=0
    local waiver_state=DISABLED waiver_report="$output_dir/waivers_applied.txt"
    local raw_report_dir="$output_dir/raw/report" raw_metrics_file="$output_dir/raw/coverage_metrics.tsv"
    local raw_value='' adjusted_value='' effective_metric
    report_dir="$output_dir/report"
    summary_file="$output_dir/coverage.log"
    [[ -f "$report_dir/dashboard.html" ]] && dashboard="$report_dir/dashboard.html"
    [[ -n "$dashboard" ]] || { [[ -f "$report_dir/dashboard.txt" ]] && dashboard="$report_dir/dashboard.txt"; }
    metrics_file="$output_dir/coverage_metrics.tsv"
    runner_coverage_parse_metrics "$report_dir" "$metrics_file" 2>/dev/null || rm -f "$metrics_file"
    if [[ -f "$output_dir/waiver.meta" ]]; then waiver_state=REQUESTED; fi
    if [[ -f "$waiver_report" ]]; then waiver_state=APPLIED; fi
    if [[ "$waiver_state" != DISABLED && -d "$raw_report_dir" ]]; then
        runner_coverage_parse_metrics "$raw_report_dir" "$raw_metrics_file" 2>/dev/null || rm -f "$raw_metrics_file"
        effective_metric="${metric:-score}"
        [[ "$effective_metric" == '-' ]] && effective_metric=score
        raw_value="$(awk -F'|' -v key="$effective_metric" '$1==key {print $2; exit}' "$raw_metrics_file" 2>/dev/null)"
        adjusted_value="$(awk -F'|' -v key="$effective_metric" '$1==key {print $2; exit}' "$metrics_file" 2>/dev/null)"
    fi
    if [[ -n "$runtime_scope" ]]; then
        runtime_summary="$(runner_runtime_scope_error_summary "$runtime_scope")"
    else
        runtime_summary="$(runner_coverage_runtime_error_summary "$output_dir/vdb_manifest.tsv")"
    fi
    IFS='|' read -r sva_errors error_total <<< "$runtime_summary"
    {
        printf '================================================================================\nCoverage Summary\n'
        printf 'Status       : %s\nMetric       : %s\nValue        : %s\nTarget       : %s\n' "$status" "${metric:--}" "${value:--}" "${target:--}"
        printf 'Waivers      : %s\n' "$waiver_state"
        if [[ "$waiver_state" != DISABLED ]]; then
            printf 'Raw Value    : %s\nAdjusted     : %s\n' "${raw_value:-N/A}" "${adjusted_value:-N/A}"
            printf 'Raw Report   : %s\n' "$(runner_report_path "$raw_report_dir")"
            printf 'Waiver Report: %s\n' "$([[ -f "$waiver_report" ]] && runner_report_path "$waiver_report" || printf '%s' 'not generated')"
        fi
        printf 'SVA Error    : %s\nError Total  : %s\n' "$sva_errors" "$error_total"
        printf 'Report Dir   : %s\nDashboard    : %s\n' "$(runner_report_path "$report_dir")" "$([[ -n "$dashboard" ]] && runner_report_path "$dashboard" || printf '%s' 'not generated')"
        printf '%s\n' '--------------------------------------------------------------------------------'
        runner_coverage_metric_rows "$metrics_file"
        printf '================================================================================\n'
    } > "$summary_file"
    runner_write_artifact_index "$output_dir" "$output_dir/artifacts.tsv"
    if [[ "${RUNNER_REPORT_QUIET:-0}" != 1 ]]; then
        printf '\n================================================================================\n  Coverage Summary\n================================================================================\n'
        printf ' Status       : %s\n Metric       : %s\n Value        : %s\n Target       : %s\n' "$status" "${metric:--}" "${value:--}" "${target:--}"
        printf ' Waivers      : %s\n' "$waiver_state"
        if [[ "$waiver_state" != DISABLED ]]; then
            printf ' Raw Value    : %s\n Adjusted     : %s\n' "${raw_value:-N/A}" "${adjusted_value:-N/A}"
            [[ ! -f "$waiver_report" ]] || printf ' Waiver Report: %s\n' "$(runner_report_path "$waiver_report")"
        fi
        printf ' SVA Error    : %s\n Error Total  : %s\n' "$sva_errors" "$error_total"
        printf ' Summary Log  : %s\n' "$(runner_report_path "$summary_file")"
        [[ -z "$dashboard" ]] || printf ' Dashboard    : file://%s\n' "$dashboard"
        runner_coverage_metric_rows "$metrics_file" ' '
        printf '================================================================================\n'
    fi
}

runner_report_signoff() {
    local run_id="$1" root="$2" status="$3" coverage_status="$4" regression_status="$5"
    local coverage_summary="$6" regression_summary="$7"
    local summary_dir="$root/summary" summary_file="$root/summary/signoff.log"
    local coverage_sva=0 regression_sva=0 sva_errors=0
    local coverage_errors=0 regression_errors=0 error_total=0
    local coverage_waivers=DISABLED coverage_raw=N/A coverage_adjusted=N/A coverage_waiver_report='not generated'
    mkdir -p "$summary_dir"
    if [[ -f "$coverage_summary" ]]; then
        coverage_sva="$(awk '/^SVA Error[[:space:]]*:/ {sub(/^[^:]*:[[:space:]]*/, ""); print; exit}' "$coverage_summary")"
        coverage_errors="$(awk '/^Error Total[[:space:]]*:/ {sub(/^[^:]*:[[:space:]]*/, ""); print; exit}' "$coverage_summary")"
        coverage_waivers="$(awk '/^Waivers[[:space:]]*:/ {sub(/^[^:]*:[[:space:]]*/, ""); print; exit}' "$coverage_summary")"
        coverage_raw="$(awk '/^Raw Value[[:space:]]*:/ {sub(/^[^:]*:[[:space:]]*/, ""); print; exit}' "$coverage_summary")"
        coverage_adjusted="$(awk '/^Adjusted[[:space:]]*:/ {sub(/^[^:]*:[[:space:]]*/, ""); print; exit}' "$coverage_summary")"
        coverage_waiver_report="$(awk '/^Waiver Report[[:space:]]*:/ {sub(/^[^:]*:[[:space:]]*/, ""); print; exit}' "$coverage_summary")"
    fi
    if [[ -f "$regression_summary" ]]; then
        regression_sva="$(awk '/^SVA Error[[:space:]]*:/ {sub(/^[^:]*:[[:space:]]*/, ""); print; exit}' "$regression_summary")"
        regression_errors="$(awk '/^Error Total[[:space:]]*:/ {sub(/^[^:]*:[[:space:]]*/, ""); print; exit}' "$regression_summary")"
    fi
    coverage_sva="${coverage_sva:-0}"
    regression_sva="${regression_sva:-0}"
    coverage_errors="${coverage_errors:-0}"
    coverage_waivers="${coverage_waivers:-DISABLED}"
    coverage_raw="${coverage_raw:-N/A}"
    coverage_adjusted="${coverage_adjusted:-N/A}"
    coverage_waiver_report="${coverage_waiver_report:-not generated}"
    regression_errors="${regression_errors:-0}"
    [[ "$coverage_sva" =~ ^[0-9]+$ ]] || coverage_sva=0
    [[ "$regression_sva" =~ ^[0-9]+$ ]] || regression_sva=0
    [[ "$coverage_errors" =~ ^[0-9]+$ ]] || coverage_errors=0
    [[ "$regression_errors" =~ ^[0-9]+$ ]] || regression_errors=0
    sva_errors=$((coverage_sva + regression_sva))
    error_total=$((coverage_errors + regression_errors))
    {
        printf '================================================================================\nSignoff Summary\n'
        printf 'Run ID       : %s\nStatus       : %s\n' "$run_id" "$status"
        printf 'Coverage     : %s\nRegression   : %s\n' "$coverage_status" "$regression_status"
        printf 'Waivers      : %s\n' "$coverage_waivers"
        if [[ "$coverage_waivers" != DISABLED ]]; then
            printf 'Raw Value    : %s\nAdjusted     : %s\nWaiver Report: %s\n' \
                "$coverage_raw" "$coverage_adjusted" "$coverage_waiver_report"
        fi
        printf 'SVA Error    : %s\n' "$sva_errors"
        printf 'Error Total  : %s\n' "$error_total"
        printf 'Completed    : %s\n================================================================================\n' "$(date -Is)"
    } > "$summary_file"
    if [[ "${RUNNER_REPORT_QUIET:-0}" != 1 ]]; then
        printf '\n================================================================================\n  Signoff Summary\n================================================================================\n'
        printf ' Status       : %s\n Coverage     : %s\n Regression   : %s\n' "$status" "$coverage_status" "$regression_status"
        printf ' Waivers      : %s\n' "$coverage_waivers"
        if [[ "$coverage_waivers" != DISABLED ]]; then
            printf ' Raw Value    : %s\n Adjusted     : %s\n Waiver Report: %s\n' \
                "$coverage_raw" "$coverage_adjusted" "$coverage_waiver_report"
        fi
        printf ' SVA Error    : %s\n Error Total  : %s\n Summary Log  : %s\n' "$sva_errors" "$error_total" "$(runner_report_path "$summary_file")"
        printf '================================================================================\n'
    fi
}
