#!/usr/bin/env bash

runner_coverage_value() {
    local cov_dir="$1" metric="$2" resolver="${3:-}" value
    if [[ -f "$cov_dir/coverage_metrics.tsv" ]]; then
        value="$(awk -F'|' -v metric="$metric" '$1==metric {print $2; exit}' "$cov_dir/coverage_metrics.tsv")"
        [[ -n "$value" ]] && { printf '%s\n' "$value"; return 0; }
    fi
    if runner_coverage_parse_metrics "$cov_dir/report" "$cov_dir/coverage_metrics.tsv" 2>/dev/null; then
        value="$(awk -F'|' -v metric="$metric" '$1==metric {print $2; exit}' "$cov_dir/coverage_metrics.tsv")"
        [[ -n "$value" ]] && { printf '%s\n' "$value"; return 0; }
    fi
    if [[ -n "$resolver" ]]; then
        runner_info "Coverage metric source=project-command metric=$metric" >&2
        value="$(COV_DIR="$cov_dir" COVERAGE_METRIC="$metric" eval "$resolver" 2>/dev/null)" || return 2
        value="$(printf '%s\n' "$value" | grep -Eo '[0-9]+([.][0-9]+)?' | tail -n 1)"
        [[ -n "$value" ]] && { printf '%s\n' "$value"; return 0; }
    fi
    value="$("$RUNNER_SCRIPT_DIR/runner_make.sh" -s coverage-value "COV_DIR=$cov_dir" "COVERAGE_METRIC=$metric" 2>/dev/null)" || return 2
    value="$(printf '%s\n' "$value" | grep -Eo '[0-9]+([.][0-9]+)?' | tail -n 1)"
    [[ -n "$value" ]] || return 2
    printf '%s\n' "$value"
}

runner_coverage_meets_target() {
    awk -v value="$1" -v target="$2" 'BEGIN {exit !(value+0 >= target+0)}'
}

runner_coverage_once_tests() {
    local testplan="$1"
    awk -F'|' '
        /^#[[:space:]]*DV_TESTPLAN_VERSION=2/ {v2=1; next}
        /^[[:space:]]*#/ || /^[[:space:]]*$/ {next}
        {tags=v2?$9:$8}
        index("," tags ",", ",coverage-iteration=once,") {print $1}
    ' "$testplan"
}

runner_coverage_validate_case_schema() {
    local case_file="$1" bad_line
    bad_line="$(awk -F'|' 'NF != 20 && NF != 23 {print NR; exit}' "$case_file")"
    if [[ -n "$bad_line" ]]; then
        runner_error "Coverage case database schema mismatch: expected 20 or 23 fields at ${case_file}:${bad_line}"
        return 1
    fi
}

runner_coverage_publish_regression_summaries() {
    local closure_root="$1" summary_dir="$1/summary"
    local regression_log="$summary_dir/regression.log" failures_log="$summary_dir/failures.log"
    local iteration_dir iteration case_file case_total case_passed case_failed
    local total_iterations=0 total_cases=0 total_passed=0 total_failed=0 case_index row_error
    local timestamp burst burst_attempt test_name case_id level plusargs seed seed_attempt result rc reason case_duration log_file
    local warnings errors fatals sva_errors scoreboard_failed error_total dump_status dump_format dump_file
    local -a iteration_dirs=()
    while IFS= read -r iteration_dir; do iteration_dirs+=("$iteration_dir"); done \
        < <(find "$closure_root/iterations" -mindepth 1 -maxdepth 1 -type d -name 'I[0-9][0-9][0-9]' 2>/dev/null | sort)
    ((${#iteration_dirs[@]} > 0)) || return 0

    for iteration_dir in "${iteration_dirs[@]}"; do
        case_file="$iteration_dir/summary/regression.cases.latest.tsv"
        [[ -r "$case_file" ]] || continue
        runner_coverage_validate_case_schema "$case_file" || return $?
        case_total="$(wc -l < "$case_file" | tr -d '[:space:]')"
        case_passed="$(awk -F'|' '$10=="PASS" {n++} END {print n+0}' "$case_file")"
        case_failed=$((case_total - case_passed))
        total_iterations=$((total_iterations + 1))
        total_cases=$((total_cases + case_total))
        total_passed=$((total_passed + case_passed))
        total_failed=$((total_failed + case_failed))
    done
    ((total_iterations > 0)) || return 0

    mkdir -p "$summary_dir"
    {
        printf '================================================================================\nCoverage Regression Summary\n'
        printf 'Run ID         : %s\nStatus         : %s\nIterations     : %s\nTotal Cases    : %s\nPassed         : %s\nFailed         : %s\n' \
            "$(basename "$closure_root")" "$([[ $total_failed -eq 0 ]] && printf PASS || printf FAIL)" \
            "$total_iterations" "$total_cases" "$total_passed" "$total_failed"
        printf 'Failures Log   : %s\n================================================================================\n' "$(runner_report_path "$failures_log")"
        for iteration_dir in "${iteration_dirs[@]}"; do
            iteration="$(basename "$iteration_dir")"
            case_file="$iteration_dir/summary/regression.cases.latest.tsv"
            [[ -r "$case_file" ]] || continue
            case_total="$(wc -l < "$case_file" | tr -d '[:space:]')"
            case_passed="$(awk -F'|' '$10=="PASS" {n++} END {print n+0}' "$case_file")"
            case_failed=$((case_total - case_passed)); case_index=0
            printf '\n--------------------------------------------------------------------------------\n[ITERATION %s]\nCases          : %s\nPassed         : %s\nFailed         : %s\nManifest       : %s\n--------------------------------------------------------------------------------\n' \
                "$iteration" "$case_total" "$case_passed" "$case_failed" \
                "$(runner_report_path "$iteration_dir/metadata/manifest.tsv")"
            while IFS='|' read -r timestamp burst burst_attempt test_name case_id level plusargs seed seed_attempt result rc reason case_duration log_file warnings errors fatals sva_errors scoreboard_failed error_total dump_status dump_format dump_file; do
                case_index=$((case_index + 1))
                if [[ "$error_total" =~ ^[0-9]+$ ]]; then row_error="$error_total"
                else row_error="$(runner_log_metric_count "$log_file" ERROR_TOTAL)"
                fi
                [[ "$case_id" == "$test_name" ]] && case_id=default
                printf '[CASE-RESULT %s/%s]\nIteration     : %s\nStatus        : %s\nBurst         : %s\nTest          : %s\nCase          : %s\nLevel         : %s\nPlusargs      : %s\nSeed          : %s\n' \
                    "$case_index" "$case_total" "$iteration" "$result" "$burst" "$test_name" \
                    "${case_id:-default}" "${level:--}" "${plusargs:-none}" "$seed"
                printf 'Burst Attempt : %s\nSeed Attempt  : %s\nRC            : %s\nReason        : %s\nTime          : %s\n' \
                    "$burst_attempt" "$seed_attempt" "$rc" "$reason" "$(runner_report_duration "${case_duration:-0}")"
                printf 'UVM W/E/F     : %s/%s/%s\nSVA Error     : %s\nError Total   : %s\n' \
                    "${warnings:-0}" "${errors:-0}" "${fatals:-0}" "${sva_errors:-0}" "$row_error"
                printf 'Dump Status   : %s\nDump Format   : %s\nDump File     : %s\n' \
                    "${dump_status:-DISABLED}" "${dump_format:-none}" \
                    "$([[ -n "$dump_file" ]] && runner_report_path "$dump_file" || printf '%s' '-')"
                local attempt_number="${burst_attempt#A}"
                printf 'Compile Log   : %s\nDetail Log    : %s\n--------------------------------------------------------------------------------\n' \
                    "$(runner_report_compile_log_path "$iteration_dir/bursts/$burst/attempt_$attempt_number")" \
                    "$(runner_report_path "$log_file")"
            done < "$case_file"
        done
        printf '================================================================================\nOverall Result\nStatus         : %s\nIterations     : %s\nTotal Cases    : %s\nPassed         : %s\nFailed         : %s\n================================================================================\n' \
            "$([[ $total_failed -eq 0 ]] && printf PASS || printf FAIL)" "$total_iterations" "$total_cases" "$total_passed" "$total_failed"
    } > "$regression_log"

    : > "$failures_log"; case_index=0
    for iteration_dir in "${iteration_dirs[@]}"; do
        iteration="$(basename "$iteration_dir")"; case_file="$iteration_dir/summary/regression.cases.latest.tsv"
        [[ -r "$case_file" ]] || continue
        while IFS='|' read -r timestamp burst burst_attempt test_name case_id level plusargs seed seed_attempt result rc reason case_duration log_file warnings errors fatals sva_errors scoreboard_failed error_total dump_status dump_format dump_file; do
            [[ "$result" == FAIL ]] || continue
            case_index=$((case_index + 1))
            [[ "$case_id" == "$test_name" ]] && case_id=default
            printf '[FAIL %s/%s]\nIteration : %s\nBurst     : %s\nTest      : %s\nCase      : %s\nLevel     : %s\nPlusargs  : %s\nSeed      : %s\nReason    : %s\nLog       : %s\n--------------------------------------------------------------------------------\n' \
                "$case_index" "$total_failed" "$iteration" "$burst" "$test_name" \
                "${case_id:-default}" "${level:--}" "${plusargs:-none}" "$seed" "$reason" \
                "$(runner_report_path "$log_file")" >> "$failures_log"
        done < "$case_file"
    done
    [[ -s "$failures_log" ]] || printf 'No failed cases.\n' > "$failures_log"
    runner_publish_html_summary "$closure_root"
}

runner_coverage_publish_summary() {
    local closure_root="$1" output_dir="$2" coverage_log tmp_log regression_log failures_log
    mkdir -p "$closure_root/summary"
    runner_coverage_publish_regression_summaries "$closure_root" || return $?
    coverage_log="$closure_root/summary/coverage.log"
    regression_log="$closure_root/summary/regression.log"
    failures_log="$closure_root/summary/failures.log"
    if [[ -f "$output_dir/coverage.log" ]]; then
        cp "$output_dir/coverage.log" "$coverage_log"
        if [[ -f "$regression_log" ]]; then
            tmp_log="$coverage_log.tmp"
            awk -v regression="$(runner_report_path "$regression_log")" -v failures="$(runner_report_path "$failures_log")" \
                '{print} /^Error Total[[:space:]]*:/ {printf "Regression Log: %s\nFailures Log  : %s\n", regression, failures}' \
                "$coverage_log" > "$tmp_log" && mv "$tmp_log" "$coverage_log"
        fi
    fi
    runner_publish_html_summary "$closure_root"
    # Iteration reports and the merged coverage output already own scoped
    # artifact indexes. Re-indexing the entire closure tree here duplicated
    # that work and delayed Command Execution Summary after coverage was done.
}

runner_run_coverage() {
    local no_merge=0 skip_report=0 has_test=0 test_count=0 target=0 metric='score' max_seeds=3 max_seeds_explicit=0 check_interval=1 stop_on_target=1 probe=0
    local run_id='' scheduler="${DV_DEFAULT_SCHEDULER:-auto}" cpus=1 timeout_sec=0 idle_timeout_sec=0 show_output=0 allow_miss=0 apply_waiver=0
    local waiver_file="${DV_COV_WAIVER_FILE:-}" waiver_manifest="${DV_COV_WAIVER_MANIFEST:-}"
    local timeout_explicit=0 idle_timeout_explicit=0 case_order_explicit=0 test_file=''
    local log_style="${RUNNER_LOG_STYLE:-compact}" show_worker_output=0
    local -a forwarded=()
    while (($#)); do
        case "$1" in
            --no-merge|--skip-merge) no_merge=1; shift ;;
            --skip-report) skip_report=1; shift ;;
            --target|--coverage-target) target="$2"; shift 2 ;;
            --target-metric|--coverage-metric) metric="$2"; shift 2 ;;
            --max-seeds) max_seeds="$2"; max_seeds_explicit=1; shift 2 ;;
            --check-interval) check_interval="$2"; shift 2 ;;
            --stop-on-target) stop_on_target=1; shift ;;
            --no-stop-on-target) stop_on_target=0; shift ;;
            --allow-miss|--allow-coverage-miss) allow_miss=1; shift ;;
            --waiver|--apply-waivers) apply_waiver=1; shift ;;
            --waiver-file) waiver_file="$2"; apply_waiver=1; shift 2 ;;
            --waiver-manifest) waiver_manifest="$2"; apply_waiver=1; shift 2 ;;
            --probe) probe=1; max_seeds=1; max_seeds_explicit=1; target=0; shift ;;
            -f|--file) test_file="$2"; shift 2 ;;
            -t|--test) test_count=$((test_count + 1)); forwarded+=("$1" "$2"); shift 2 ;;
            --id|--run-id) run_id="$2"; shift 2 ;;
            --scheduler) scheduler="$2"; forwarded+=("$1" "$2"); shift 2 ;;
            --cpus) cpus="$2"; forwarded+=("$1" "$2"); shift 2 ;;
            --timeout) timeout_sec="$2"; timeout_explicit=1; forwarded+=("$1" "$2"); shift 2 ;;
            --idle-timeout) idle_timeout_sec="$2"; idle_timeout_explicit=1; forwarded+=("$1" "$2"); shift 2 ;;
            --show-output) show_output=1; forwarded+=("$1"); shift ;;
            --show-worker-output) show_worker_output=1; log_style='verbose'; shift ;;
            --log-style) log_style="$2"; shift 2 ;;
            --compact-log) log_style='compact'; shift ;;
            --verbose-log) log_style='verbose'; shift ;;
            --case-order) case_order_explicit=1; forwarded+=("$1" "$2"); shift 2 ;;
            *) forwarded+=("$1"); shift ;;
        esac
    done
    ((test_count == 1)) && has_test=1
    if ((apply_waiver && no_merge)); then
        runner_die "--waiver requires coverage merge; remove --no-merge/--skip-merge"
        return $?
    fi
    [[ "$target" =~ ^[0-9]+([.][0-9]+)?$ ]] || { runner_die "Invalid coverage target: $target"; return $?; }
    case "$metric" in score|line|cond|toggle|fsm|branch|assert|group) ;; *) runner_die "Invalid coverage metric: $metric"; return $?;; esac
    case "$log_style" in compact|verbose) ;; *) runner_die "Invalid log style: $log_style"; return $?;; esac
    [[ "$log_style" != compact ]] || show_worker_output=0
    runner_require_uint --max-seeds "$max_seeds" || return $?; runner_require_uint --check-interval "$check_interval" || return $?
    ((max_seeds > 0 && check_interval > 0)) || { runner_die "max-seeds and check-interval must be positive"; return $?; }
    if awk -v t="$target" 'BEGIN {exit !(t <= 0)}' && ((max_seeds_explicit == 0)); then
        max_seeds=1
    fi
    runner_prepare_out_dir
    [[ -n "$run_id" ]] || run_id="$(runner_new_id coverage)"
    local closure_root="$(runner_runs_dir)/$run_id" output_dir="$(runner_out_dir)/coverage/$run_id"
    local metadata_dir="$closure_root/metadata" run_meta="$closure_root/metadata/run.meta"
    mkdir -p "$closure_root/iterations" "$closure_root/summary" "$metadata_dir" "$output_dir"
    runner_update_latest_run "$run_id" coverage
    printf 'run_id=%s\nkind=coverage\ntarget=%s\nmetric=%s\nwaivers=%s\nlog_style=%s\ncreated=%s\n' \
        "$run_id" "$target" "$metric" "$([[ $apply_waiver -eq 1 ]] && printf applied || printf disabled)" "$log_style" "$(date -Is)" > "$run_meta"
    local testplan_snapshot='' once_tests_csv=''
    if ((has_test == 0)); then
        if [[ -z "$test_file" ]]; then
            # Snapshot only a freshly normalized plan so source-list comments
            # take effect in every coverage iteration.
            runner_project_generate >/dev/null || return $?
            test_file="${TEST_LIST_FILE:-$(runner_make_value print-test-list)}"
        fi
        [[ "$test_file" == /* ]] || test_file="$RUNNER_ROOT/$test_file"
        [[ -r "$test_file" ]] || { runner_die "Coverage test-list file is not readable: $test_file"; return $?; }
        testplan_snapshot="$metadata_dir/testplan.snapshot.dv"
        cp "$test_file" "$testplan_snapshot"
        if declare -F dv_project_prepare_coverage_testplan >/dev/null 2>&1; then
            dv_project_prepare_coverage_testplan "$testplan_snapshot" || return $?
        fi
        once_tests_csv="$(runner_coverage_once_tests "$testplan_snapshot" | paste -sd, -)"
        printf 'testplan_snapshot=%s\ncoverage_once_tests=%s\n' "$testplan_snapshot" "${once_tests_csv:-none}" >> "$run_meta"
    fi
    if [[ "$log_style" == verbose ]]; then
        runner_panel_begin "Coverage Execution Plan"
        runner_panel_value "Run ID" "$run_id"
        runner_panel_value Mode "$([[ $has_test -eq 1 ]] && printf single-test || printf regression)"
        runner_panel_value Target "$target"
        runner_panel_value Metric "$metric"
        runner_panel_value "Max Iterations" "$max_seeds"
        runner_panel_value "Check Interval" "$check_interval"
        runner_panel_value "Stop On Target" "$stop_on_target"
        runner_panel_value "VDB Policy" "latest PASS attempts only"
        runner_panel_value "Compile Policy" "independent compile per burst"
        runner_panel_value Waivers "$([[ $apply_waiver -eq 1 ]] && printf applied || printf disabled)"
        runner_panel_end
    else
        printf '[COVERAGE] run=%s mode=%s metric=%s target=%s iterations=%s\n' \
            "$run_id" "$([[ $has_test -eq 1 ]] && printf single-test || printf regression)" "$metric" "$target" "$max_seeds"
    fi

    local iteration rc=0 value='' reached=0 once_test coverage_status=PASS
    for ((iteration=1; iteration<=max_seeds; iteration++)); do
        local iteration_dir="$closure_root/iterations/I$(printf '%03d' "$iteration")"
        mkdir -p "$iteration_dir"
        local -a args=("${forwarded[@]}" --cov --id "$run_id" --run-dir "$iteration_dir")
        if ((has_test == 0)); then
            args+=(--log-style "$log_style" --file "$testplan_snapshot")
            ((case_order_explicit)) || args+=(--case-order seed-major)
            if ((iteration > 1)) && [[ -n "$once_tests_csv" ]]; then
                runner_split_csv "$once_tests_csv"
                for once_test in "${RUNNER_SPLIT_RESULT[@]}"; do args+=(--exclude-test "$once_test"); done
            fi
        fi
        ((show_worker_output && has_test == 0)) && args+=(--show-worker-output)
        if ((iteration > 1)); then
            args+=(--rand-num 1)
        fi
        if [[ "$log_style" == compact ]]; then printf '[COV-RUN %02d/%02d] execute\n' "$iteration" "$max_seeds"
        else runner_info "Coverage iteration=$iteration/$max_seeds run=$run_id"
        fi
        if ((has_test)) && [[ "$log_style" == compact && "$show_worker_output" == 0 ]]; then
            local worker_console="$iteration_dir/worker.console.log"
            RUNNER_REPORT_QUIET=1 runner_run_test "${args[@]}" > "$worker_console" 2>&1 || rc=$?
            if ((rc == 0)); then printf '[COV-PASS %02d/%02d] test iteration complete\n' "$iteration" "$max_seeds"
            else
                printf '[COV-FAIL %02d/%02d] log=%s\n' "$iteration" "$max_seeds" "$(runner_report_path "$worker_console")"
                if [[ -f "$iteration_dir/summary/failure_quick_links.log" ]]; then
                    printf 'Failure Quick Links\n%s\n' '--------------------------------------------------------------------------------'
                    cat "$iteration_dir/summary/failure_quick_links.log"
                fi
            fi
        elif ((has_test)); then
            runner_run_test "${args[@]}" || rc=$?
        else
            runner_run_regression "${args[@]}" || rc=$?
        fi
        if ((rc != 0)); then
            runner_report_coverage "$output_dir" FAIL "$metric" not-available "$target" "$closure_root"
            printf 'status=%s\ncoverage_status=run-fail\ncompleted=%s\n' "$rc" "$(date -Is)" >> "$run_meta"
            runner_coverage_publish_summary "$closure_root" "$output_dir"
            return "$rc"
        fi

        if ((no_merge == 0 && (iteration % check_interval == 0 || iteration == max_seeds) )); then
            local -a merge_args=(--scope "$closure_root" --run-id "$run_id" --output-dir "$output_dir"
                --scheduler "$scheduler" --cpus "$cpus")
            ((timeout_explicit)) && merge_args+=(--timeout "$timeout_sec")
            ((idle_timeout_explicit)) && merge_args+=(--idle-timeout "$idle_timeout_sec")
            if [[ "$metric" != score ]] && awk -v t="$target" 'BEGIN {exit !(t > 0)}'; then
                merge_args+=(--require-metrics "$metric")
            fi
            ((show_output)) && merge_args+=(--show-output)
            if ((apply_waiver)); then
                merge_args+=(--waiver --waiver-file "$waiver_file" --waiver-manifest "$waiver_manifest")
            fi
            if [[ "$log_style" == compact && "$show_worker_output" == 0 ]]; then
                local merge_console="$output_dir/merge.console.log" merge_rc=0
                printf '[COV-MERGE %02d/%02d] databases=latest-PASS\n' "$iteration" "$max_seeds"
                RUNNER_REPORT_QUIET=1 runner_merge_coverage "${merge_args[@]}" > "$merge_console" 2>&1 || merge_rc=$?
                if ((merge_rc != 0)); then
                    printf '[COV-MERGE-FAIL] log=%s\n' "$(runner_report_path "$merge_console")"
                    return "$merge_rc"
                fi
            else
                RUNNER_REPORT_QUIET=1 runner_merge_coverage "${merge_args[@]}" || return $?
            fi
            if awk -v t="$target" 'BEGIN {exit !(t > 0)}'; then
                if [[ "$log_style" == verbose ]]; then
                    runner_info "Coverage metric resolver dashboard=$([[ -f "$output_dir/report/dashboard.txt" ]] && printf yes || printf no) project_command=$([[ -n "${COVERAGE_VALUE_CMD:-}" ]] && printf configured || printf missing)"
                fi
                value="$(runner_coverage_value "$output_dir" "$metric" "${COVERAGE_VALUE_CMD:-}")" || {
                    runner_die "Coverage metric was not found in URG dashboard and COVERAGE_VALUE_CMD did not provide it"; return $?; }
                printf '%s|%s|%s|%s\n' "$(date -Is)" "$iteration" "$metric" "$value" >> "$closure_root/coverage_history.tsv"
                if [[ "$log_style" == compact ]]; then printf '[COV-METRIC %02d/%02d] %s=%s target=%s\n' "$iteration" "$max_seeds" "$metric" "$value" "$target"
                else runner_info "Coverage metric=$metric value=$value target=$target"
                fi
                if runner_coverage_meets_target "$value" "$target"; then reached=1; ((stop_on_target)) && break; fi
            fi
        fi
        ((probe)) && break
    done

    if awk -v t="$target" 'BEGIN {exit !(t > 0)}' && ((reached == 0)); then
        runner_warn "Coverage target not reached: metric=$metric value=${value:-unknown} target=$target"
        if ((allow_miss)); then
            coverage_status=MISS_ALLOWED
        else
            runner_report_coverage "$output_dir" FAIL "$metric" "${value:-unknown}" "$target" "$closure_root"
            printf 'status=1\ncoverage_status=target-miss\ncompleted=%s\n' "$(date -Is)" >> "$run_meta"
            runner_coverage_publish_summary "$closure_root" "$output_dir"
            [[ "$log_style" != compact ]] || printf '[FAIL] COVERAGE run=%s %s=%s target=%s report=%s\n' \
                "$run_id" "$metric" "${value:-unknown}" "$target" "$(runner_report_path "$output_dir/report")"
            return 1
        fi
    fi
    ((skip_report)) && runner_info "--skip-report requested; merge command may still produce its tool-default report"
    printf 'status=0\ncoverage_status=%s\ncompleted=%s\n' "$coverage_status" "$(date -Is)" >> "$run_meta"
    runner_report_coverage "$output_dir" "$coverage_status" "$metric" "${value:-not-requested}" "$target" "$closure_root"
    runner_coverage_publish_summary "$closure_root" "$output_dir" || return $?
    if [[ "$log_style" == compact ]]; then
        if [[ "$coverage_status" == PASS ]]; then
            printf '[PASS] COVERAGE run=%s %s=%s target=%s report=%s\n' \
                "$run_id" "$metric" "${value:-not-requested}" "$target" "$(runner_report_path "$output_dir/report")"
        else
            printf '[MISS-ALLOWED] COVERAGE run=%s %s=%s target=%s report=%s\n' \
                "$run_id" "$metric" "${value:-unknown}" "$target" "$(runner_report_path "$output_dir/report")"
        fi
    fi
}
