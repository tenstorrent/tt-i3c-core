#!/usr/bin/env bash

runner_regression_append_status() {
    local line="$1" lock_file="${REG_STATUS_FILE}.lock"
    if command -v flock >/dev/null 2>&1; then
        { flock 9; printf '%s\n' "$line" >> "$REG_STATUS_FILE"; } 9>"$lock_file"
    else
        printf '%s\n' "$line" >> "$REG_STATUS_FILE"
    fi
}

runner_regression_append_case_status() {
    local line="$1" lock_file="${REG_CASE_STATUS_FILE}.lock"
    if command -v flock >/dev/null 2>&1; then
        { flock 9; printf '%s\n' "$line" >> "$REG_CASE_STATUS_FILE"; } 9>"$lock_file"
    else
        printf '%s\n' "$line" >> "$REG_CASE_STATUS_FILE"
    fi
}

runner_regression_append_reported_case() {
    local line="$1" lock_file="${REG_REPORTED_CASE_FILE}.lock"
    if command -v flock >/dev/null 2>&1; then
        { flock 9; printf '%s\n' "$line" >> "$REG_REPORTED_CASE_FILE"; } 9>"$lock_file"
    else
        printf '%s\n' "$line" >> "$REG_REPORTED_CASE_FILE"
    fi
}

runner_regression_attempt_reason() {
    local attempt_dir="$1" rc="$2" file reason fallback='UNKNOWN'
    if ((rc == 0)); then printf 'PASS\n'; return; fi
    local compile_log="$attempt_dir/compile_logs/compile.log" tests_root="$attempt_dir/tests"
    [[ -f "$compile_log" ]] || compile_log="$attempt_dir/logs/compile/compile.log"
    [[ -d "$tests_root" ]] || tests_root="$attempt_dir/cases"
    if [[ -f "$compile_log" ]] &&
       ! find "$tests_root" -type f -name 'sim.log' -print -quit 2>/dev/null | grep -q .; then
        reason="$(runner_failure_reason "$rc" "$compile_log")"
        case "$reason" in
            TOOL_FAIL|INFRA_FAIL|LICENSE_FAIL|DISK_FAIL|SCHEDULER_FAIL|TIMEOUT)
                printf '%s\n' "$reason"
                ;;
            *)
                printf 'COMPILE_FAIL\n'
                ;;
        esac
        return
    fi
    while IFS= read -r -d '' file; do
        reason="$(runner_failure_reason "$rc" "$file")"
        case "$reason" in
            TEST_FAIL|UVM_FAIL|ASSERT_FAIL|SCOREBOARD_FAIL|ERROR_FAIL) printf '%s\n' "$reason"; return ;;
            TOOL_FAIL|INFRA_FAIL|LICENSE_FAIL|DISK_FAIL|SCHEDULER_FAIL|TIMEOUT) fallback="$reason" ;;
        esac
    done < <(find "$attempt_dir" -type f -name '*.log' -print0 2>/dev/null)
    printf '%s\n' "$fallback"
}

runner_regression_record_case_results() {
    local attempt_dir="$1" burst_id="$2" burst_attempt="$3" test_name="$4" seeds="$5" burst_status="$6" burst_rc="$7" burst_reason="$8"
    local case_id="${9:-$test_name}" level="${10:--}" plusargs="${11:-}"
    local summary="$attempt_dir/summary/seeds.latest.tsv" error_totals="$attempt_dir/summary/error_totals.tsv" seed seed_attempt status rc reason duration log_file
    local warnings errors fatals sva_errors scoreboard_failed dump_status dump_format dump_file timestamp error_total
    if [[ -s "$summary" ]]; then
        while IFS='|' read -r seed seed_attempt status rc reason duration log_file warnings errors fatals sva_errors scoreboard_failed dump_status dump_file; do
            timestamp="$(date -Is)"
            error_total="$(awk -F'|' -v seed="$seed" -v attempt="$seed_attempt" \
                '$1==seed && $2==attempt {print $3; exit}' "$error_totals" 2>/dev/null)"
            [[ "$error_total" =~ ^[0-9]+$ ]] || error_total="$(runner_log_metric_count "$log_file" ERROR_TOTAL)"
            dump_format="$(runner_report_dump_format "${dump_status:-DISABLED}" "$dump_file" none)"
            runner_regression_append_case_status "$timestamp|$burst_id|A$(printf '%03d' "$burst_attempt")|$test_name|$case_id|$level|$plusargs|$seed|$seed_attempt|$status|$rc|$reason|$duration|$log_file|${warnings:-0}|${errors:-0}|${fatals:-0}|${sva_errors:-0}|${scoreboard_failed:-0}|${error_total:-0}|${dump_status:-DISABLED}|$dump_format|$dump_file"
        done < "$summary"
        return
    fi
    runner_split_csv "$seeds"
    for seed in "${RUNNER_SPLIT_RESULT[@]}"; do
        timestamp="$(date -Is)"
        error_total="$(runner_log_metric_count "$attempt_dir/console.log" ERROR_TOTAL)"
        runner_regression_append_case_status "$timestamp|$burst_id|A$(printf '%03d' "$burst_attempt")|$test_name|$case_id|$level|$plusargs|$seed|-|$burst_status|$burst_rc|$burst_reason|0|$attempt_dir/console.log|0|0|0|0|0|${error_total:-0}|DISABLED|none|"
    done
}

runner_regression_compact_enabled() {
    [[ "${REG_LOG_STYLE:-compact}" == compact && "${REG_SHOW_WORKER_OUTPUT:-0}" == 0 ]]
}

runner_regression_level_code() {
    case "$1" in
        light) printf 'L' ;;
        medium|med) printf 'M' ;;
        heavy|high) printf 'H' ;;
        extra) printf 'X' ;;
        *) printf '?' ;;
    esac
}

runner_regression_prepare_case_index() {
    local index seed case_count=0
    REG_PLAN_CASE_BASE=(); REG_PLAN_CASE_COUNT=()
    for index in "$@"; do
        runner_split_csv "${REG_PLAN_SEEDS[$index]}"
        REG_PLAN_CASE_BASE[$index]="$case_count"
        REG_PLAN_CASE_COUNT[$index]="${#RUNNER_SPLIT_RESULT[@]}"
        for seed in "${RUNNER_SPLIT_RESULT[@]}"; do case_count=$((case_count + 1)); done
    done
    REG_TOTAL_CASES="$case_count"
}

runner_regression_print_start() {
    local index="$1" attempt="$2" seed case_display level_code
    case_display="${REG_PLAN_CASE_ID[$index]}"
    [[ "$case_display" == "${REG_PLAN_TEST[$index]}" ]] && case_display='-'
    level_code="$(runner_regression_level_code "${REG_PLAN_LEVEL[$index]}")"
    runner_split_csv "${REG_PLAN_SEEDS[$index]}"
    for seed in "${RUNNER_SPLIT_RESULT[@]}"; do
        printf '[START] %s A%03d %s S=%-10s T=%-60s C=%s\n' \
            "${REG_PLAN_BURST[$index]}" "$attempt" "$level_code" "$seed" \
            "${REG_PLAN_TEST[$index]}" "$case_display"
    done
}

runner_regression_print_result() {
    local index="$1" attempt="$2"
    local burst_id="${REG_PLAN_BURST[$index]}" test_name="${REG_PLAN_TEST[$index]}"
    local case_display="${REG_PLAN_CASE_ID[$index]}" level_code
    local attempt_dir result rc=1 reason=UNKNOWN status=FAIL summary seed seed_attempt seed_status seed_rc seed_reason duration log_file
    local warnings errors fatals sva_errors scoreboard_failed dump_status dump_file
    [[ "$case_display" == "$test_name" ]] && case_display='-'
    level_code="$(runner_regression_level_code "${REG_PLAN_LEVEL[$index]}")"
    if ((attempt <= 0)); then
        attempt="$(awk -F'|' -v b="$burst_id" 'NR>1 && $2==b {a=$3; gsub(/^A/,"",a); if(a+0>max)max=a+0} END {print max+0}' "$REG_STATUS_FILE")"
    fi
    attempt_dir="$REG_RUN_DIR/bursts/$burst_id/attempt_$(printf '%03d' "$attempt")"
    result="$attempt_dir/attempt.result"
    if [[ -r "$result" ]]; then IFS='|' read -r rc reason status < "$result"; fi
    summary="$attempt_dir/summary/seeds.latest.tsv"
    if [[ -s "$summary" ]]; then
        while IFS='|' read -r seed seed_attempt seed_status seed_rc seed_reason duration log_file warnings errors fatals sva_errors scoreboard_failed dump_status dump_file; do
            runner_report_case_result "$seed_status" "$burst_id" "$attempt" "$test_name" "$seed" "$seed_rc" \
                "${seed_reason:-$reason}" "$log_file" "$level_code" "$case_display"
            runner_regression_append_reported_case "$(date -Is)|$burst_id|A$(printf '%03d' "$attempt")|$test_name|$seed|$seed_attempt|$seed_status"
        done < "$summary"
    else
        runner_split_csv "${REG_PLAN_SEEDS[$index]}"
        log_file="$attempt_dir/console.log"
        for seed in "${RUNNER_SPLIT_RESULT[@]}"; do
            runner_report_case_result FAIL "$burst_id" "$attempt" "$test_name" "$seed" "$rc" "$reason" "$log_file" \
                "$level_code" "$case_display"
            runner_regression_append_reported_case "$(date -Is)|$burst_id|A$(printf '%03d' "$attempt")|$test_name|$seed|-|FAIL"
        done
    fi
}

runner_regression_print_final_heartbeat() {
    local status_file="$1" start_epoch="$2" tests="$3" cases="$4" counts passed failed
    counts="$(awk -F'|' 'NR>1 {latest[$2 SUBSEP $5]=$7} END {for (item in latest) {if (latest[item]=="PASS") p++; else if (latest[item]=="FAIL") f++} print p+0"|"f+0}' "$status_file")"
    passed="${counts%%|*}"; failed="${counts#*|}"
    printf '[HEARTBEAT] PHASE=complete SCOPE=regression elapsed=%s tests=%s cases=%s pass=%s fail=%s\n' \
        "$(runner_format_duration "$(( $(date +%s) - start_epoch ))")" "$tests" "$cases" "$passed" "$failed"
}

runner_regression_launch_gap() {
    local delay="$1" parent_start="$2" completed="$3" total="$4" active="$5" queued="$6" oldest="${7:-}" detail_root="${8:-}"
    local elapsed=0 interval="${REG_HEARTBEAT_SEC:-1}"
    [[ "$interval" =~ ^[0-9]+$ ]] || interval=1
    ((delay > 0)) || return 0
    if ! runner_regression_compact_enabled || ((active == 0)); then
        sleep "$delay"
        return 0
    fi
    while ((elapsed < delay)); do
        if ((interval > 0 && elapsed % interval == 0)); then
            runner_parent_live_status "$REG_LIVE_MODE" bursts "$parent_start" "$completed" "$total" "$active" "$queued" "$oldest" "$detail_root"
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    runner_live_clear "$REG_LIVE_MODE"
}

runner_regression_attempt_worker() {
    local index="$1" wave_attempt="$2" attempt burst_id test_name case_display seeds plusargs compile_requirements attempt_dir worker rc=0 reason status
    attempt=$(( ${REG_PLAN_ATTEMPT_BASE[$index]:-0} + wave_attempt ))
    burst_id="${REG_PLAN_BURST[$index]}"; test_name="${REG_PLAN_TEST[$index]}"
    case_display="${REG_PLAN_CASE_ID[$index]}"; [[ "$case_display" == "$test_name" ]] && case_display=default
    seeds="${REG_PLAN_SEEDS[$index]}"; plusargs="${REG_PLAN_PLUSARGS[$index]}"
    compile_requirements="${REG_PLAN_COMPILE_REQUIREMENTS[$index]:-}"
    attempt_dir="$REG_RUN_DIR/bursts/$burst_id/attempt_$(printf '%03d' "$attempt")"
    worker="$REG_WORKER"
    if ((wave_attempt > 1)) && [[ "$REG_RETRY_WAVE_WORKER" != 'inherit' ]]; then worker="$REG_RETRY_WAVE_WORKER"; fi
    if [[ "$REG_DEGRADED_MODE" == '1' || ( "$REG_DEGRADED_MODE" == 'final' && "$attempt" -eq "$REG_TOTAL_ATTEMPTS" ) ]]; then
        [[ "$REG_DEGRADED_WORKER" == 'inherit' ]] || worker="$REG_DEGRADED_WORKER"
    fi
    mkdir -p "$attempt_dir"

    if runner_regression_compact_enabled; then
        printf 'Run Metadata\n'
        printf '  Burst   : %s\n  Attempt : A%03d\n  Level   : %s\n' "$burst_id" "$attempt" "${REG_PLAN_LEVEL[$index]}"
        printf '  Seeds   : %s\n  Test    : %s\n  Case    : %s\n' "$seeds" "$test_name" "$case_display"
        printf '  Plusargs: %s\n%s\n' "${plusargs:-none}" '--------------------------------------------------------------------------------'
    fi

    local -a args=(-t "$test_name" --seeds "$seeds" --jobs "$worker" --scheduler "$REG_SCHEDULER"
        --cpus "$REG_CPUS" --timeout "$REG_TIMEOUT_SEC" --idle-timeout "$REG_IDLE_TIMEOUT_SEC"
        --run-id "$REG_RUN_ID" --run-dir "$attempt_dir" --burst-id "$burst_id"
        --seed-retry-max "$REG_SEED_RETRY_MAX" --verbosity "$REG_VERBOSITY"
        --dump-format "$REG_DUMP_FORMAT" --heartbeat-sec "$REG_HEARTBEAT_SEC"
        --hang-warn-sec "$REG_HANG_WARN_SEC" --hang-kill-sec "$REG_HANG_KILL_SEC"
        --hang-pending-kill-sec "$REG_HANG_PENDING_KILL_SEC"
        --hang-min-elapsed-sec "$REG_HANG_MIN_ELAPSED_SEC" --hang-low-cpu-pct "$REG_HANG_LOW_CPU_PCT")
    if [[ "${REG_PARENT_LIVE:-0}" == 1 ]]; then args+=(--live-quiet); else args+=(--live-mode "$REG_LIVE_MODE"); fi
    [[ -n "$plusargs" ]] && args+=(--plusargs "$plusargs")
    args+=(--compile-requirements "$compile_requirements")
    ((REG_COV)) && args+=(--cov)
    ((REG_CONN)) && args+=(--conn)
    ((REG_SHOW_OUTPUT)) && args+=(--show-output)
    ((REG_INCLUDE_WARNINGS)) && args+=(--include-warnings)
    RUNNER_REPORT_QUIET=1 runner_run_test "${args[@]}" || rc=$?
    reason="$(runner_regression_attempt_reason "$attempt_dir" "$rc")"
    ((rc == 0)) && status=PASS || status=FAIL
    printf '%s|%s|%s\n' "$rc" "$reason" "$status" > "$attempt_dir/attempt.result"
    runner_regression_record_case_results "$attempt_dir" "$burst_id" "$attempt" "$test_name" "$seeds" "$status" "$rc" "$reason" \
        "${REG_PLAN_CASE_ID[$index]}" "${REG_PLAN_LEVEL[$index]}" "$plusargs"
    runner_regression_append_status "$(date -Is)|$burst_id|A$(printf '%03d' "$attempt")|$status|$rc|$reason|$attempt_dir"
    return "$rc"
}

# Wait for whichever child finishes first while preserving the aggregate
# parallel heartbeat. The old scheduler waited on array element zero, so a
# slow first burst withheld already-complete later results and left a worker
# slot idle until that first burst exited.
runner_regression_wait_any() {
    local pids_name="$1" indexes_name="$2" mode="$3" scope="$4"
    local start_epoch="$5" completed="$6" total="$7" queued="$8"
    local -n pids_ref="$pids_name" indexes_ref="$indexes_name"
    local interval="${REG_HEARTBEAT_SEC:-1}" last now slot pid detail_index rc

    [[ "$interval" =~ ^[0-9]+$ ]] || interval=1
    last="$(date +%s)"
    runner_live_open_output || true
    while :; do
        for slot in "${!pids_ref[@]}"; do
            pid="${pids_ref[$slot]}"
            if ! kill -0 "$pid" 2>/dev/null; then
                rc=0
                wait "$pid" || rc=$?
                REG_COMPLETED_SLOT="$slot"
                REG_COMPLETED_PID="$pid"
                REG_COMPLETED_RC="$rc"
                runner_live_clear "$mode"
                runner_live_close_output
                return "$rc"
            fi
        done

        now="$(date +%s)"
        if ((interval > 0 && now - last >= interval)); then
            detail_index="${indexes_ref[0]}"
            runner_parent_live_status "$mode" "$scope" "$start_epoch" \
                "$completed" "$total" "${#pids_ref[@]}" "$queued" \
                "BURST=${REG_PLAN_BURST[$detail_index]}" \
                "$REG_RUN_DIR/bursts/${REG_PLAN_BURST[$detail_index]}"
            last="$now"
        fi
        sleep 1
    done
}

runner_regression_run_wave() {
    local attempt="$1" max_parallel="$2" start_gap="$3"
    shift 3
    local -a indexes=("$@") active_pids=() active_indexes=()
    local index pid i rc active_index gap_index completed_slot overall=0 completed=0 dispatched=0 total=${#indexes[@]} parent_start actual_attempt attempt_dir console_log
    parent_start="$(date +%s)"; REG_PARENT_LIVE=0
    runner_regression_compact_enabled && ((total > 0)) && REG_PARENT_LIVE=1
    for index in "${indexes[@]}"; do
        if ((dispatched > 0 && start_gap > 0)); then
            if ((${#active_indexes[@]} > 0)); then
                gap_index="${active_indexes[0]}"
                runner_regression_launch_gap "$start_gap" "$parent_start" "$completed" "$total" "${#active_pids[@]}" \
                    "$((total - dispatched))" "BURST=${REG_PLAN_BURST[$gap_index]}" "$REG_RUN_DIR/bursts/${REG_PLAN_BURST[$gap_index]}"
            fi
        fi
        actual_attempt=$(( ${REG_PLAN_ATTEMPT_BASE[$index]:-0} + attempt ))
        attempt_dir="$REG_RUN_DIR/bursts/${REG_PLAN_BURST[$index]}/attempt_$(printf '%03d' "$actual_attempt")"
        console_log="$attempt_dir/console.log"; mkdir -p "$attempt_dir"
        if runner_regression_compact_enabled; then
            ((REG_PARENT_LIVE)) && runner_live_clear "$REG_LIVE_MODE"
            runner_regression_print_start "$index" "$actual_attempt"
        fi
        if ! runner_regression_compact_enabled; then
            runner_info "[DISPATCH $((dispatched + 1))/$total] burst=${REG_PLAN_BURST[$index]} attempt=A$(printf '%03d' "$actual_attempt") test=${REG_PLAN_TEST[$index]} compile=private console=$console_log"
        fi
        if runner_regression_compact_enabled; then runner_regression_attempt_worker "$index" "$attempt" > "$console_log" 2>&1 &
        else runner_regression_attempt_worker "$index" "$attempt" &
        fi
        active_pids+=("$!"); active_indexes+=("$index"); dispatched=$((dispatched + 1))
        if ((${#active_pids[@]} >= max_parallel)); then
            runner_regression_wait_any active_pids active_indexes \
                "$([[ $REG_PARENT_LIVE -eq 1 ]] && printf '%s' "$REG_LIVE_MODE" || printf quiet)" \
                bursts "$parent_start" "$completed" "$total" "$((total - dispatched))" || overall=1
            completed_slot="$REG_COMPLETED_SLOT"
            active_index="${active_indexes[$completed_slot]}"
            completed=$((completed + 1))
            if runner_regression_compact_enabled; then
                ((REG_PARENT_LIVE)) && runner_live_clear "$REG_LIVE_MODE"
                actual_attempt=$(( ${REG_PLAN_ATTEMPT_BASE[$active_index]:-0} + attempt ))
                runner_regression_print_result "$active_index" "$actual_attempt"
            fi
            unset 'active_pids[completed_slot]' 'active_indexes[completed_slot]'
            active_pids=("${active_pids[@]}"); active_indexes=("${active_indexes[@]}")
        fi
    done
    while ((${#active_pids[@]})); do
        runner_regression_wait_any active_pids active_indexes \
            "$([[ $REG_PARENT_LIVE -eq 1 ]] && printf '%s' "$REG_LIVE_MODE" || printf quiet)" \
            bursts "$parent_start" "$completed" "$total" 0 || overall=1
        completed_slot="$REG_COMPLETED_SLOT"
        active_index="${active_indexes[$completed_slot]}"
        completed=$((completed + 1))
        if runner_regression_compact_enabled; then
            ((REG_PARENT_LIVE)) && runner_live_clear "$REG_LIVE_MODE"
            actual_attempt=$(( ${REG_PLAN_ATTEMPT_BASE[$active_index]:-0} + attempt ))
            runner_regression_print_result "$active_index" "$actual_attempt"
        fi
        unset 'active_pids[completed_slot]' 'active_indexes[completed_slot]'
        active_pids=("${active_pids[@]}"); active_indexes=("${active_indexes[@]}")
    done
    ((REG_PARENT_LIVE)) && runner_live_clear "$REG_LIVE_MODE"
    return "$overall"
}

runner_regression_immediate_worker() {
    local index="$1" wave_attempt=1 actual_attempt rc=1 result reason repeated
    while ((wave_attempt <= REG_TOTAL_ATTEMPTS)); do
        actual_attempt=$(( ${REG_PLAN_ATTEMPT_BASE[$index]:-0} + wave_attempt ))
        runner_regression_attempt_worker "$index" "$wave_attempt"; rc=$?
        ((rc == 0)) && return 0
        result="$REG_RUN_DIR/bursts/${REG_PLAN_BURST[$index]}/attempt_$(printf '%03d' "$actual_attempt")/attempt.result"
        reason="$(cut -d'|' -f2 "$result" 2>/dev/null)"
        runner_reason_retryable "$reason" || return "$rc"
        repeated="$(awk -F'|' -v b="${REG_PLAN_BURST[$index]}" -v r="$reason" 'NR>1 && $2==b && $6==r {n++} END {print n+0}' "$REG_STATUS_FILE")"
        if [[ "$reason" == TOOL_FAIL && "$repeated" -ge 2 ]]; then
            runner_error "[RETRY-BAILOUT] burst=${REG_PLAN_BURST[$index]} reason=$reason repeated=${repeated}x"
            return "$rc"
        fi
        wave_attempt=$((wave_attempt + 1))
        runner_warn "[RETRY] burst=${REG_PLAN_BURST[$index]} next_attempt=A$(printf '%03d' "$((actual_attempt + 1))") reason=$reason"
        local delay="$REG_RETRY_DELAY_SEC"
        if [[ "$REG_DEGRADED_MODE" == '1' || ( "$REG_DEGRADED_MODE" == 'final' && "$wave_attempt" -eq "$REG_TOTAL_ATTEMPTS" ) ]]; then
            ((REG_DEGRADED_DELAY_SEC > delay)) && delay="$REG_DEGRADED_DELAY_SEC"
        fi
        ((wave_attempt <= REG_TOTAL_ATTEMPTS && delay > 0)) && sleep "$delay"
    done
    return "$rc"
}

runner_regression_run_immediate() {
    local -a indexes=("$@") pids=() active_indexes=()
    local index pid active_index gap_index completed_slot overall=0 completed=0 dispatched=0 total=$# parent_start console_log
    parent_start="$(date +%s)"; REG_PARENT_LIVE=0
    runner_regression_compact_enabled && ((total > 0)) && REG_PARENT_LIVE=1
    for index in "${indexes[@]}"; do
        if ((dispatched > 0 && REG_BURST_START_GAP_SEC > 0)); then
            if ((${#active_indexes[@]} > 0)); then
                gap_index="${active_indexes[0]}"
                runner_regression_launch_gap "$REG_BURST_START_GAP_SEC" "$parent_start" "$completed" "$total" "${#pids[@]}" \
                    "$((total - dispatched))" "BURST=${REG_PLAN_BURST[$gap_index]}" "$REG_RUN_DIR/bursts/${REG_PLAN_BURST[$gap_index]}"
            fi
        fi
        console_log="$REG_RUN_DIR/bursts/${REG_PLAN_BURST[$index]}/console.immediate.log"; mkdir -p "$(dirname "$console_log")"
        if runner_regression_compact_enabled; then
            ((REG_PARENT_LIVE)) && runner_live_clear "$REG_LIVE_MODE"
            runner_regression_print_start "$index" "$(( ${REG_PLAN_ATTEMPT_BASE[$index]:-0} + 1 ))"
        fi
        if ! runner_regression_compact_enabled; then
            runner_info "[DISPATCH $((dispatched + 1))/$total] burst=${REG_PLAN_BURST[$index]} retry=immediate compile=private console=$console_log"
        fi
        if runner_regression_compact_enabled; then runner_regression_immediate_worker "$index" > "$console_log" 2>&1 &
        else runner_regression_immediate_worker "$index" &
        fi
        pids+=("$!"); active_indexes+=("$index"); dispatched=$((dispatched + 1))
        if ((${#pids[@]} >= REG_BURST_MAX)); then
            runner_regression_wait_any pids active_indexes \
                "$([[ $REG_PARENT_LIVE -eq 1 ]] && printf '%s' "$REG_LIVE_MODE" || printf quiet)" \
                bursts "$parent_start" "$completed" "$total" "$((total - dispatched))" || overall=1
            completed_slot="$REG_COMPLETED_SLOT"
            active_index="${active_indexes[$completed_slot]}"
            completed=$((completed + 1))
            if runner_regression_compact_enabled; then
                ((REG_PARENT_LIVE)) && runner_live_clear "$REG_LIVE_MODE"
                runner_regression_print_result "$active_index" 0
            fi
            unset 'pids[completed_slot]' 'active_indexes[completed_slot]'
            pids=("${pids[@]}"); active_indexes=("${active_indexes[@]}")
        fi
    done
    while ((${#pids[@]})); do
        runner_regression_wait_any pids active_indexes \
            "$([[ $REG_PARENT_LIVE -eq 1 ]] && printf '%s' "$REG_LIVE_MODE" || printf quiet)" \
            bursts "$parent_start" "$completed" "$total" 0 || overall=1
        completed_slot="$REG_COMPLETED_SLOT"
        active_index="${active_indexes[$completed_slot]}"
        completed=$((completed + 1))
        if runner_regression_compact_enabled; then
            ((REG_PARENT_LIVE)) && runner_live_clear "$REG_LIVE_MODE"
            runner_regression_print_result "$active_index" 0
        fi
        unset 'pids[completed_slot]' 'active_indexes[completed_slot]'
        pids=("${pids[@]}"); active_indexes=("${active_indexes[@]}")
    done
    ((REG_PARENT_LIVE)) && runner_live_clear "$REG_LIVE_MODE"
    return "$overall"
}

runner_regression_normalize_level() {
    case "${1,,}" in
        light|lite) printf 'light' ;;
        medium|med) printf 'medium' ;;
        heavy|high) printf 'heavy' ;;
        extra) printf 'extra' ;;
        *) printf 'medium' ;;
    esac
}

runner_regression_parse_burst_metadata() {
    local file="$1" line payload token key value
    REG_BURST_LIMIT_LIGHT=20; REG_BURST_LIMIT_MEDIUM=10; REG_BURST_LIMIT_HEAVY=5; REG_BURST_LIMIT_EXTRA=1
    REG_BURST_PLAN_LIGHT='test-major'; REG_BURST_PLAN_MEDIUM='test-major'
    REG_BURST_PLAN_HEAVY='test-major'; REG_BURST_PLAN_EXTRA='test-major'
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#${line%%[![:space:]]*}}"
        [[ "$line" == '# BURST_LIMITS '* || "$line" == '# BURST_PLAN '* ]] || continue
        payload="${line#\# BURST_LIMITS }"
        if [[ "$payload" == "$line" ]]; then payload="${line#\# BURST_PLAN }"; fi
        for token in $payload; do
            key="${token%%=*}"; value="${token#*=}"
            case "$line:$key" in
                '# BURST_LIMITS '*:light) REG_BURST_LIMIT_LIGHT="$value" ;;
                '# BURST_LIMITS '*:medium) REG_BURST_LIMIT_MEDIUM="$value" ;;
                '# BURST_LIMITS '*:heavy) REG_BURST_LIMIT_HEAVY="$value" ;;
                '# BURST_LIMITS '*:extra) REG_BURST_LIMIT_EXTRA="$value" ;;
                '# BURST_PLAN '*:light) REG_BURST_PLAN_LIGHT="$value" ;;
                '# BURST_PLAN '*:medium) REG_BURST_PLAN_MEDIUM="$value" ;;
                '# BURST_PLAN '*:heavy) REG_BURST_PLAN_HEAVY="$value" ;;
                '# BURST_PLAN '*:extra) REG_BURST_PLAN_EXTRA="$value" ;;
            esac
        done
    done < "$file"
    for value in "$REG_BURST_LIMIT_LIGHT" "$REG_BURST_LIMIT_MEDIUM" "$REG_BURST_LIMIT_HEAVY" "$REG_BURST_LIMIT_EXTRA"; do
        [[ "$value" =~ ^[1-9][0-9]*$ ]] || {
            runner_error "BURST_LIMITS values must be positive integers in $file"
            return 2
        }
    done
    for value in "$REG_BURST_PLAN_LIGHT" "$REG_BURST_PLAN_MEDIUM" "$REG_BURST_PLAN_HEAVY" "$REG_BURST_PLAN_EXTRA"; do
        case "$value" in
            test-major|seed-major) ;;
            *) runner_error "Unsupported BURST_PLAN '$value' in $file; use test-major or seed-major"; return 2 ;;
        esac
    done
}

runner_regression_level_limit() {
    case "$1" in
        light) printf '%s' "$REG_BURST_LIMIT_LIGHT" ;;
        medium) printf '%s' "$REG_BURST_LIMIT_MEDIUM" ;;
        heavy) printf '%s' "$REG_BURST_LIMIT_HEAVY" ;;
        extra) printf '%s' "$REG_BURST_LIMIT_EXTRA" ;;
    esac
}

runner_regression_level_plan() {
    case "$1" in
        light) printf '%s' "$REG_BURST_PLAN_LIGHT" ;;
        medium) printf '%s' "$REG_BURST_PLAN_MEDIUM" ;;
        heavy) printf '%s' "$REG_BURST_PLAN_HEAVY" ;;
        extra) printf '%s' "$REG_BURST_PLAN_EXTRA" ;;
    esac
}

runner_regression_append_burst() {
    local name="$1" case_id="$2" group="$3" seeds="$4" plusargs="$5" level="$6"
    local index=$(( ${#REG_PLAN_TEST[@]} + 1 ))
    REG_PLAN_TEST+=("$name"); REG_PLAN_GROUP+=("$group"); REG_PLAN_SEEDS+=("$seeds")
    REG_PLAN_CASE_ID+=("$case_id")
    REG_PLAN_PLUSARGS+=("$plusargs"); REG_PLAN_LEVEL+=("$level")
    REG_PLAN_BURST+=("B$(printf '%03d' "$index")")
}

runner_regression_tag_value() {
    local tags="$1" key="$2" token
    runner_split_csv "$tags"
    for token in "${RUNNER_SPLIT_RESULT[@]}"; do
        if [[ "$token" == "$key="* ]]; then
            printf '%s\n' "${token#*=}"
            return 0
        fi
    done
    return 1
}

runner_regression_apply_seed_policy() {
    local policy="${1:-all}" seeds="$2" fixed cap
    case "$policy" in
        all|'') printf '%s\n' "$seeds" ;;
        first) printf '%s\n' "${seeds%%,*}" ;;
        random-one)
            runner_split_csv "$seeds"
            ((${#RUNNER_SPLIT_RESULT[@]} > 0)) || return 2
            printf '%s\n' "${RUNNER_SPLIT_RESULT[$((RANDOM % ${#RUNNER_SPLIT_RESULT[@]}))]}"
            ;;
        fixed:*)
            fixed="${policy#fixed:}"
            [[ "$fixed" =~ ^[1-9][0-9]*$ ]] || return 2
            printf '%s\n' "$fixed"
            ;;
        cap:*)
            cap="${policy#cap:}"
            [[ "$cap" =~ ^[1-9][0-9]*$ ]] || return 2
            runner_split_csv "$seeds"
            ((${#RUNNER_SPLIT_RESULT[@]} > 0)) || return 2
            printf '%s\n' "$(IFS=,; echo "${RUNNER_SPLIT_RESULT[*]:0:cap}")"
            ;;
        *) return 2 ;;
    esac
}

runner_regression_load_plan() {
    local file="$1" include_off="$2" seeds_override="$3" rand_num="$4" case_order="$5" coverage_mode="${6:-0}"
    shift 6
    local -a selectors=("$@") raw_name=() raw_case_id=() raw_group=() raw_level=() raw_seeds=() raw_plusargs=() raw_compile_requirements=()
    local version name case_id group level enabled seed_policy seeds plusargs tags compile_requirements selector matched random_seeds='' line
    local effective_seed_policy coverage_seed_policy
    local planning_level mode limit raw_index seed_index max_seeds offset chunk_csv
    local -a level_indexes=() test_seeds=() chunk=()
    REG_PLAN_TEST=(); REG_PLAN_CASE_ID=(); REG_PLAN_GROUP=(); REG_PLAN_SEEDS=(); REG_PLAN_PLUSARGS=(); REG_PLAN_LEVEL=(); REG_PLAN_BURST=(); REG_PLAN_COMPILE_REQUIREMENTS=()
    version="$(sed -n 's/^#[[:space:]]*DV_TESTPLAN_VERSION=\([0-9][0-9]*\).*/\1/p' "$file" | head -1)"
    [[ "$version" == 1 || "$version" == 2 ]] || {
        runner_error "Unsupported or missing DV_TESTPLAN_VERSION header: $file"
        return 2
    }
    runner_regression_parse_burst_metadata "$file" || return $?
    if ((rand_num > 0)); then
        runner_random_seeds "$rand_num"
        random_seeds="$(IFS=,; echo "${RUNNER_RANDOM_SEEDS[*]}")"
    fi
    while IFS= read -r line; do
        if [[ "$version" == 2 ]]; then
            IFS='|' read -r name case_id group level enabled seed_policy seeds plusargs tags compile_requirements <<< "$line"
        else
            IFS='|' read -r name group level enabled seed_policy seeds plusargs tags compile_requirements <<< "$line"
            case_id="$name"
        fi
        name="${name#${name%%[![:space:]]*}}"; name="${name%${name##*[![:space:]]}}"
        [[ -n "$name" && "${name:0:1}" != '#' ]] || continue
        case_id="${case_id#${case_id%%[![:space:]]*}}"; case_id="${case_id%${case_id##*[![:space:]]}}"
        [[ "$case_id" =~ ^[A-Za-z0-9_.-]+$ ]] || { runner_error "Invalid case_id '$case_id' for $name"; return 2; }
        enabled="${enabled:-on}"; level="$(runner_regression_normalize_level "${level:-medium}")"
        [[ "$include_off" == 1 || "$enabled" != 'off' ]] || continue
        matched=0
        if ((${#selectors[@]} == 0)); then matched=1; fi
        for selector in "${selectors[@]}"; do
            [[ "$selector" == "test:$name" || "$selector" == "case:$case_id" || "$selector" == "group:$group" || "$selector" == "level:$level" ]] && matched=1
        done
        ((matched)) || continue
        if [[ ",${REG_EXCLUDED_TESTS_CSV}," == *",$name,"* || ",${REG_EXCLUDED_GROUPS_CSV}," == *",$group,"* ]]; then continue; fi
        if [[ -n "$seeds_override" ]]; then seeds="$seeds_override"
        elif [[ -n "$random_seeds" && ",$tags," == *,random-seed,* ]]; then seeds="$random_seeds"
        else seeds="${seeds:-1}"
        fi
        effective_seed_policy="${seed_policy:-all}"
        if ((coverage_mode)); then
            coverage_seed_policy="$(runner_regression_tag_value "$tags" coverage-seed 2>/dev/null || true)"
            [[ -z "$coverage_seed_policy" ]] || effective_seed_policy="$coverage_seed_policy"
        fi
        seeds="$(runner_regression_apply_seed_policy "$effective_seed_policy" "$seeds")" || {
            runner_error "Invalid seed policy '$effective_seed_policy' for $name"
            return 2
        }
        raw_name+=("$name"); raw_case_id+=("$case_id"); raw_group+=("$group"); raw_level+=("$level")
        raw_seeds+=("$seeds"); raw_plusargs+=("$plusargs"); raw_compile_requirements+=("$compile_requirements")
    done < "$file"

    for planning_level in light medium heavy extra; do
        level_indexes=()
        for raw_index in "${!raw_name[@]}"; do
            [[ "${raw_level[$raw_index]}" == "$planning_level" ]] && level_indexes+=("$raw_index")
        done
        ((${#level_indexes[@]} > 0)) || continue
        mode="$case_order"
        [[ "$mode" != auto ]] || mode="$(runner_regression_level_plan "$planning_level")"
        limit="$(runner_regression_level_limit "$planning_level")"
        if [[ "$mode" == test-major ]]; then
            for raw_index in "${level_indexes[@]}"; do
                runner_split_csv "${raw_seeds[$raw_index]}"; test_seeds=("${RUNNER_SPLIT_RESULT[@]}")
                for ((offset=0; offset<${#test_seeds[@]}; offset+=limit)); do
                    chunk=("${test_seeds[@]:offset:limit}")
                    chunk_csv="$(IFS=,; echo "${chunk[*]}")"
                    runner_regression_append_burst "${raw_name[$raw_index]}" "${raw_case_id[$raw_index]}" "${raw_group[$raw_index]}" \
                        "$chunk_csv" "${raw_plusargs[$raw_index]}" "$planning_level"
                    REG_PLAN_COMPILE_REQUIREMENTS+=("${raw_compile_requirements[$raw_index]}")
                done
            done
        else
            max_seeds=0
            for raw_index in "${level_indexes[@]}"; do
                runner_split_csv "${raw_seeds[$raw_index]}"
                ((${#RUNNER_SPLIT_RESULT[@]} > max_seeds)) && max_seeds="${#RUNNER_SPLIT_RESULT[@]}"
            done
            for ((seed_index=0; seed_index<max_seeds; seed_index++)); do
                for raw_index in "${level_indexes[@]}"; do
                    runner_split_csv "${raw_seeds[$raw_index]}"; test_seeds=("${RUNNER_SPLIT_RESULT[@]}")
                    ((seed_index < ${#test_seeds[@]})) || continue
                    runner_regression_append_burst "${raw_name[$raw_index]}" "${raw_case_id[$raw_index]}" "${raw_group[$raw_index]}" \
                        "${test_seeds[$seed_index]}" "${raw_plusargs[$raw_index]}" "$planning_level"
                    REG_PLAN_COMPILE_REQUIREMENTS+=("${raw_compile_requirements[$raw_index]}")
                done
            done
        fi
    done
}

runner_regression_write_manifest() {
    local i
    printf 'burst_id|test|case_id|group|seeds|plusargs|level|compile_requirements\n' > "$REG_MANIFEST_FILE"
    for i in "${!REG_PLAN_TEST[@]}"; do
        printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "${REG_PLAN_BURST[$i]}" "${REG_PLAN_TEST[$i]}" "${REG_PLAN_CASE_ID[$i]}" \
            "${REG_PLAN_GROUP[$i]}" "${REG_PLAN_SEEDS[$i]}" "${REG_PLAN_PLUSARGS[$i]}" "${REG_PLAN_LEVEL[$i]}" \
            "${REG_PLAN_COMPILE_REQUIREMENTS[$i]:-}" >> "$REG_MANIFEST_FILE"
    done
}

runner_regression_load_manifest() {
    local file="$1" burst_id test_name case_id group seeds plusargs level compile_requirements manifest_v2=0 line
    grep -q '^burst_id|test|case_id|' "$file" && manifest_v2=1
    REG_PLAN_TEST=(); REG_PLAN_CASE_ID=(); REG_PLAN_GROUP=(); REG_PLAN_SEEDS=(); REG_PLAN_PLUSARGS=(); REG_PLAN_LEVEL=(); REG_PLAN_BURST=(); REG_PLAN_COMPILE_REQUIREMENTS=()
    while IFS= read -r line; do
        if ((manifest_v2)); then IFS='|' read -r burst_id test_name case_id group seeds plusargs level compile_requirements <<< "$line"
        else IFS='|' read -r burst_id test_name group seeds plusargs level compile_requirements <<< "$line"; case_id="$test_name"
        fi
        [[ "$burst_id" == B* ]] || continue
        # Backward-compatible reruns: manifests written before the requirement
        # column inherit current metadata from the normalized test plan.
        [[ -n "$compile_requirements" ]] || compile_requirements="$(runner_test_compile_requirements "$test_name")"
        REG_PLAN_BURST+=("$burst_id"); REG_PLAN_TEST+=("$test_name"); REG_PLAN_CASE_ID+=("$case_id"); REG_PLAN_GROUP+=("$group")
        REG_PLAN_SEEDS+=("$seeds"); REG_PLAN_PLUSARGS+=("$plusargs"); REG_PLAN_LEVEL+=("$level")
        REG_PLAN_COMPILE_REQUIREMENTS+=("$compile_requirements")
    done < "$file"
}

runner_run_regression() {
    local test_file='' group_csv='' level_csv='' case_csv='' seeds_override='' rand_num=0 include_off=0 all=0
    local jobs=1 auto_parallel=0 burst_max=1 burst_delay_sec=30 burst_start_gap_sec=1
    local retry_max=3 retry_delay_sec=30 retry_schedule='deferred-wave' retry_wave_burst_max='inherit' retry_wave_worker='inherit'
    local degraded_mode='final' degraded_worker='inherit' degraded_delay_sec=60 seed_retry_max=3
    local scheduler="${DV_DEFAULT_SCHEDULER:-auto}" cpus=1 timeout_sec=0 idle_timeout_sec=0 show_output=0
    local dump_format='none' cov=0 conn=0 include_warnings=0 verbosity='UVM_LOW'
    local run_id='' run_dir_override='' rerun_bursts='' rerun_failed=0 list_bursts=0 case_order='auto'
    local heartbeat_sec=1 hang_warn_sec=150 hang_kill_sec=450 hang_pending_kill_sec=3600
    local hang_min_elapsed_sec=120 hang_low_cpu_pct=2 live_mode='auto'
    local log_style="${RUNNER_LOG_STYLE:-compact}" show_worker_output=0
    local exclude_tests='' exclude_groups=''
    local report_start report_state_file='' report_heartbeat_pid='' report_rc=0
    local -a explicit_tests=()

    while (($#)); do
        case "$1" in
            -f|--file) test_file="$2"; shift 2 ;;
            -t|--test) explicit_tests+=("$2"); shift 2 ;;
            --case) case_csv="${case_csv:+$case_csv,}$2"; shift 2 ;;
            -g|--group|--label) group_csv="${group_csv:+$group_csv,}$2"; shift 2 ;;
            --level) level_csv="${level_csv:+$level_csv,}$2"; shift 2 ;;
            --exclude-test) exclude_tests="${exclude_tests:+$exclude_tests,}$2"; shift 2 ;;
            --exclude-label|--exclude-group) exclude_groups="${exclude_groups:+$exclude_groups,}$2"; shift 2 ;;
            --all) all=1; shift ;;
            --include-off) include_off=1; shift ;;
            --list-groups) test_file="${test_file:-$(runner_make_value print-test-list)}"; [[ "$test_file" == /* ]] || test_file="$RUNNER_ROOT/$test_file"; awk -F'|' '!/^[[:space:]]*#/ && NF {print $2}' "$test_file" | sort -u; return ;;
            -s|--seeds) seeds_override="$2"; shift 2 ;;
            -r|--rand-num) rand_num="$2"; shift 2 ;;
            -p|--parallel) auto_parallel=1; shift ;;
            --worker|--jobs) jobs="$2"; shift 2 ;;
            --burst-max) burst_max="$2"; shift 2 ;;
            --cpoint-max|--burst-jobs) burst_max="$2"; shift 2 ;;
            --burst-parallel) burst_max="$(runner_auto_jobs)"; shift ;;
            --burst-delay-sec) burst_delay_sec="$2"; shift 2 ;;
            --burst-start-gap-sec) burst_start_gap_sec="$2"; shift 2 ;;
            --case-order) case_order="$2"; shift 2 ;;
            --attempt-retry-max) retry_max="$2"; shift 2 ;;
            --no-attempt-retry) retry_max=0; shift ;;
            --attempt-retry-delay-sec) retry_delay_sec="$2"; shift 2 ;;
            --retry-schedule) retry_schedule="$2"; shift 2 ;;
            --retry-immediate) retry_schedule='immediate'; shift ;;
            --retry-deferred-wave) retry_schedule='deferred-wave'; shift ;;
            --retry-wave-burst-max) retry_wave_burst_max="$2"; shift 2 ;;
            --retry-wave-worker) retry_wave_worker="$2"; shift 2 ;;
            --degraded-retry) degraded_mode='1'; shift ;;
            --no-degraded-retry) degraded_mode='0'; shift ;;
            --degraded-retry-mode) degraded_mode="$2"; shift 2 ;;
            --degraded-retry-worker) degraded_worker="$2"; shift 2 ;;
            --degraded-retry-delay-sec) degraded_delay_sec="$2"; shift 2 ;;
            --no-degraded-retry-clean) shift ;;
            --seed-retry-max) seed_retry_max="$2"; shift 2 ;;
            --scheduler) scheduler="$2"; shift 2 ;;
            --cpus) cpus="$2"; shift 2 ;;
            --timeout) timeout_sec="$2"; shift 2 ;;
            --idle-timeout) idle_timeout_sec="$2"; shift 2 ;;
            --show-output) show_output=1; shift ;;
            --show-worker-output) show_worker_output=1; log_style='verbose'; shift ;;
            --log-style) log_style="$2"; shift 2 ;;
            --compact-log) log_style='compact'; shift ;;
            --verbose-log) log_style='verbose'; shift ;;
            --include-warnings) include_warnings=1; shift ;;
            --dump) dump_format='fsdb'; shift ;;
            --dump-format) dump_format="$2"; shift 2 ;;
            --cov) cov=1; shift ;;
            --conn) conn=1; shift ;;
            -v|--verb|--verbosity) verbosity="$2"; shift 2 ;;
            --id|--run-id) run_id="$2"; shift 2 ;;
            --run-dir) run_dir_override="$2"; shift 2 ;;
            --rerun-burst) rerun_bursts="$2"; shift 2 ;;
            --rerun-failed) rerun_failed=1; shift ;;
            --list-bursts) list_bursts=1; shift ;;
            --heartbeat-sec) heartbeat_sec="$2"; shift 2 ;;
            --hang-warn-sec) hang_warn_sec="$2"; shift 2 ;;
            --hang-kill-sec) hang_kill_sec="$2"; shift 2 ;;
            --hang-pending-kill-sec) hang_pending_kill_sec="$2"; shift 2 ;;
            --hang-min-elapsed-sec) hang_min_elapsed_sec="$2"; shift 2 ;;
            --hang-low-cpu-pct) hang_low_cpu_pct="$2"; shift 2 ;;
            --live-mode) live_mode="$2"; shift 2 ;;
            --live-overwrite) live_mode='overwrite'; shift ;;
            --live-line) live_mode='line'; shift ;;
            --live-quiet) live_mode='quiet'; shift ;;
            *) runner_die "Unknown regression option: $1"; return $? ;;
        esac
    done

    local value
    for value in "$rand_num" "$jobs" "$burst_max" "$burst_delay_sec" "$burst_start_gap_sec" "$retry_max" "$retry_delay_sec" "$degraded_delay_sec" "$seed_retry_max" "$cpus"; do
        runner_require_uint option "$value" || return $?
    done
    ((jobs > 0 && burst_max > 0 && cpus > 0)) || { runner_die "worker, burst-max, and cpus must be positive"; return $?; }
    case "$retry_schedule" in immediate|deferred-wave) ;; *) runner_die "Invalid retry schedule: $retry_schedule"; return $?;; esac
    case "$degraded_mode" in 0|1|final) ;; *) runner_die "Invalid degraded retry mode: $degraded_mode"; return $?;; esac
    case "$case_order" in auto|test-major|seed-major) ;; *) runner_die "Invalid case order: $case_order"; return $?;; esac
    case "$log_style" in compact|verbose) ;; *) runner_die "Invalid log style: $log_style"; return $?;; esac
    [[ "$log_style" != compact ]] || show_worker_output=0
    ((auto_parallel)) && jobs="$(runner_auto_jobs)"
    scheduler="$(runner_resolve_scheduler "$scheduler")" || return $?
    dump_format="$(runner_normalize_dump_format "$dump_format")" || return $?
    [[ "$retry_wave_burst_max" == 'inherit' ]] || runner_require_uint --retry-wave-burst-max "$retry_wave_burst_max" || return $?
    [[ "$retry_wave_worker" == 'inherit' ]] || runner_require_uint --retry-wave-worker "$retry_wave_worker" || return $?
    [[ "$degraded_worker" == 'inherit' ]] || runner_require_uint --degraded-retry-worker "$degraded_worker" || return $?

    if [[ -z "$test_file" ]]; then
        # Refresh the normalized plan before selection. Otherwise a recently
        # commented source-list entry can survive in stale generated output.
        runner_project_generate >/dev/null || return $?
        test_file="$(runner_make_value print-test-list)"
    fi
    [[ "$test_file" == /* ]] || test_file="$RUNNER_ROOT/$test_file"
    [[ -r "$test_file" ]] || { runner_die "Test-list file is not readable: $test_file"; return $?; }
    runner_prepare_out_dir
    [[ -n "$run_id" ]] || run_id="$(runner_new_id regression)"
    local run_dir="${run_dir_override:-$(runner_runs_dir)/$run_id}"
    [[ "$run_dir" == /* ]] || run_dir="$RUNNER_ROOT/$run_dir"
    mkdir -p "$run_dir/bursts" "$run_dir/summary" "$run_dir/metadata"
    local metadata_dir="$run_dir/metadata"
    local manifest_file="$metadata_dir/manifest.tsv" status_file="$metadata_dir/status.tsv" case_status_file="$metadata_dir/case_status.tsv"
    local reported_case_file="$metadata_dir/reported_cases.tsv"
    if [[ -f "$run_dir/manifest.tsv" && ! -f "$manifest_file" ]]; then
        manifest_file="$run_dir/manifest.tsv"; status_file="$run_dir/status.tsv"
        case_status_file="$run_dir/case_status.tsv"; reported_case_file="$run_dir/reported_cases.tsv"
    else
        cp "$test_file" "$metadata_dir/testplan.snapshot.dv"
        test_file="$metadata_dir/testplan.snapshot.dv"
    fi
    runner_update_latest_run "$run_id" regression
    REG_MANIFEST_FILE="$manifest_file"; REG_STATUS_FILE="$status_file"

    REG_EXCLUDED_TESTS_CSV="$exclude_tests"; REG_EXCLUDED_GROUPS_CSV="$exclude_groups"
    local -a selectors=() values=()
    local item
    for item in "${explicit_tests[@]}"; do selectors+=("test:$item"); done
    [[ -n "$case_csv" ]] && { runner_split_csv "$case_csv"; for item in "${RUNNER_SPLIT_RESULT[@]}"; do selectors+=("case:$item"); done; }
    [[ -n "$group_csv" ]] && { runner_split_csv "$group_csv"; for item in "${RUNNER_SPLIT_RESULT[@]}"; do selectors+=("group:$item"); done; }
    [[ -n "$level_csv" ]] && { runner_split_csv "$level_csv"; for item in "${RUNNER_SPLIT_RESULT[@]}"; do selectors+=("level:$item"); done; }
    runner_regression_parse_burst_metadata "$test_file" || return $?

    if [[ -f "$manifest_file" && ( $list_bursts -eq 1 || $rerun_failed -eq 1 || -n "$rerun_bursts" ) ]]; then
        runner_regression_load_manifest "$manifest_file"
    else
        runner_regression_load_plan "$test_file" "$include_off" "$seeds_override" "$rand_num" "$case_order" "$cov" "${selectors[@]}"
        runner_regression_write_manifest
        printf 'timestamp|burst_id|attempt|status|rc|reason|attempt_dir\n' > "$status_file"
    fi
    ((${#REG_PLAN_TEST[@]} > 0)) || { runner_die "No regression tests selected"; return $?; }
    if ((list_bursts)); then cat "$manifest_file"; return; fi

    local -a selected_indexes=()
    if [[ -n "$rerun_bursts" ]]; then
        runner_split_csv "$rerun_bursts"
        for item in "${RUNNER_SPLIT_RESULT[@]}"; do for value in "${!REG_PLAN_BURST[@]}"; do [[ "${REG_PLAN_BURST[$value]}" == "$item" ]] && selected_indexes+=("$value"); done; done
    elif ((rerun_failed)); then
        for value in "${!REG_PLAN_BURST[@]}"; do
            item="${REG_PLAN_BURST[$value]}"
            [[ "$(awk -F'|' -v b="$item" '$2==b {s=$4} END {print s}' "$status_file")" == 'FAIL' ]] && selected_indexes+=("$value")
        done
    else
        selected_indexes=("${!REG_PLAN_TEST[@]}")
    fi
    ((${#selected_indexes[@]} > 0)) || { runner_die "No bursts selected for execution"; return $?; }
    local selected_test_count
    local -A selected_test_names=()
    for value in "${selected_indexes[@]}"; do selected_test_names["${REG_PLAN_CASE_ID[$value]}"]=1; done
    selected_test_count="${#selected_test_names[@]}"
    runner_regression_prepare_case_index "${selected_indexes[@]}"
    printf 'timestamp|burst_id|burst_attempt|test|case_id|level|plusargs|seed|seed_attempt|status|rc|reason|duration_sec|log|uvm_warning|uvm_error|uvm_fatal|sva_error|scoreboard_failed|error_total|dump_status|dump_format|dump_file\n' > "$case_status_file"
    printf 'timestamp|burst_id|burst_attempt|test|seed|seed_attempt|status\n' > "$reported_case_file"

    REG_PLAN_ATTEMPT_BASE=()
    for value in "${!REG_PLAN_BURST[@]}"; do
        item="${REG_PLAN_BURST[$value]}"
        local latest_attempt
        latest_attempt="$(awk -F'|' -v b="$item" '$2==b {a=$3; gsub(/^A/,"",a); if(a+0>max)max=a+0} END {print max+0}' "$status_file" 2>/dev/null)"
        REG_PLAN_ATTEMPT_BASE+=("${latest_attempt:-0}")
    done

    REG_RUN_ID="$run_id" REG_RUN_DIR="$run_dir" REG_MANIFEST_FILE="$manifest_file" REG_STATUS_FILE="$status_file" REG_CASE_STATUS_FILE="$case_status_file"
    REG_REPORTED_CASE_FILE="$reported_case_file"
    RUNNER_ACTIVE_RUN_ID="$run_id"; RUNNER_ACTIVE_BURST_ID=''; RUNNER_ACTIVE_TEST='regression'
    REG_WORKER="$jobs" REG_BURST_MAX="$burst_max" REG_BURST_START_GAP_SEC="$burst_start_gap_sec"
    REG_RETRY_DELAY_SEC="$retry_delay_sec" REG_TOTAL_ATTEMPTS=$((retry_max + 1)) REG_RETRY_SCHEDULE="$retry_schedule"
    REG_DEGRADED_MODE="$degraded_mode" REG_DEGRADED_WORKER="$degraded_worker" REG_DEGRADED_DELAY_SEC="$degraded_delay_sec"
    REG_RETRY_WAVE_WORKER="$retry_wave_worker" REG_SEED_RETRY_MAX="$seed_retry_max"
    REG_SCHEDULER="$scheduler" REG_CPUS="$cpus" REG_TIMEOUT_SEC="$timeout_sec" REG_IDLE_TIMEOUT_SEC="$idle_timeout_sec"
    REG_SHOW_OUTPUT="$show_output" REG_INCLUDE_WARNINGS="$include_warnings" REG_DUMP_FORMAT="$dump_format"
    REG_COV="$cov" REG_CONN="$conn" REG_VERBOSITY="$verbosity" REG_HEARTBEAT_SEC="$heartbeat_sec"
    REG_HANG_WARN_SEC="$hang_warn_sec" REG_HANG_KILL_SEC="$hang_kill_sec" REG_HANG_PENDING_KILL_SEC="$hang_pending_kill_sec"
    REG_HANG_MIN_ELAPSED_SEC="$hang_min_elapsed_sec" REG_HANG_LOW_CPU_PCT="$hang_low_cpu_pct" REG_LIVE_MODE="$live_mode"
    REG_LOG_STYLE="$log_style" REG_SHOW_WORKER_OUTPUT="$show_worker_output"
    export REG_RUN_ID REG_RUN_DIR REG_STATUS_FILE REG_CASE_STATUS_FILE REG_REPORTED_CASE_FILE
    RUNNER_PARENT_STATUS_FILE="$reported_case_file"; RUNNER_PARENT_STATUS_KIND=regression_case
    local regression_start
    regression_start="$(date +%s)"
    printf 'run_id=%s\nkind=regression\ncase_order=%s\ntest_count=%s\nburst_count=%s\nworker=%s\nburst_max=%s\nretry_schedule=%s\nlog_style=%s\ncompile_policy=independent_per_burst\nburst_limits=light:%s,medium:%s,heavy:%s,extra:%s\nburst_plan=light:%s,medium:%s,heavy:%s,extra:%s\ncreated=%s\n' \
        "$run_id" "$case_order" "$selected_test_count" "${#selected_indexes[@]}" "$jobs" "$burst_max" "$retry_schedule" "$log_style" \
        "$REG_BURST_LIMIT_LIGHT" "$REG_BURST_LIMIT_MEDIUM" "$REG_BURST_LIMIT_HEAVY" "$REG_BURST_LIMIT_EXTRA" \
        "$REG_BURST_PLAN_LIGHT" "$REG_BURST_PLAN_MEDIUM" "$REG_BURST_PLAN_HEAVY" "$REG_BURST_PLAN_EXTRA" "$(date -Is)" > "$run_dir/metadata/run.meta"
    printf '[PLAN] Legend: S=seed T=test C=case; C=- means the default case.\n'
    if [[ "$log_style" == verbose ]]; then
        runner_report_regression_plan "$run_id" "${#selected_indexes[@]}" "$jobs" "$burst_max" "$scheduler" "$retry_schedule" \
            "$REG_TOTAL_ATTEMPTS" "$dump_format" "$cov" "$manifest_file"
        local plan_print_limit="${RUNNER_PLAN_PRINT_LIMIT:-$REG_TOTAL_CASES}" plan_position=0 seed case_display level_code
        for value in "${selected_indexes[@]}"; do
            runner_split_csv "${REG_PLAN_SEEDS[$value]}"
            for seed in "${RUNNER_SPLIT_RESULT[@]}"; do
                plan_position=$((plan_position + 1)); ((plan_position <= plan_print_limit)) || continue
                case_display="${REG_PLAN_CASE_ID[$value]}"
                [[ "$case_display" == "${REG_PLAN_TEST[$value]}" ]] && case_display='-'
                level_code="$(runner_regression_level_code "${REG_PLAN_LEVEL[$value]}")"
                printf '[PLAN] %s %s S=%-10s T=%-60s C=%s\n' \
                    "${REG_PLAN_BURST[$value]}" "$level_code" "$seed" \
                    "${REG_PLAN_TEST[$value]}" "$case_display"
            done
        done
        ((REG_TOTAL_CASES <= plan_print_limit)) || runner_info "Regression plan display truncated: shown=$plan_print_limit total=$REG_TOTAL_CASES manifest=$manifest_file"
    else
        local compact_plan_position=0 compact_plan_limit="${RUNNER_PLAN_PRINT_LIMIT:-$REG_TOTAL_CASES}" seed case_display level_code
        printf '[REGRESSION] run=%s tests=%s bursts=%s cases=%s order=%s seed_workers=%s burst_parallel=%s scheduler=%s cov=%s\n' \
            "$run_id" "$selected_test_count" "${#selected_indexes[@]}" "$REG_TOTAL_CASES" "$case_order" "$jobs" "$burst_max" "$scheduler" "$cov"
        for value in "${selected_indexes[@]}"; do
            runner_split_csv "${REG_PLAN_SEEDS[$value]}"
            for seed in "${RUNNER_SPLIT_RESULT[@]}"; do
                compact_plan_position=$((compact_plan_position + 1))
                ((compact_plan_position <= compact_plan_limit)) || continue
                level_code="$(runner_regression_level_code "${REG_PLAN_LEVEL[$value]}")"
                case_display="${REG_PLAN_CASE_ID[$value]}"
                [[ "$case_display" == "${REG_PLAN_TEST[$value]}" ]] && case_display='-'
                printf '[PLAN] %s %s S=%-10s T=%-60s C=%s\n' \
                    "${REG_PLAN_BURST[$value]}" \
                    "$level_code" "$seed" "${REG_PLAN_TEST[$value]}" "$case_display"
            done
        done
        if ((REG_TOTAL_CASES > compact_plan_limit)); then
            printf '[PLAN] truncated=%s/%s manifest=%s\n' "$compact_plan_limit" "$REG_TOTAL_CASES" "$(runner_report_path "$manifest_file")"
        else
            printf '[PLAN] manifest=%s\n' "$(runner_report_path "$manifest_file")"
        fi
    fi
    printf '%s\n' '--------------------------------------------------------------------------------'

    local overall=0
    if [[ "$retry_schedule" == 'immediate' ]]; then
        runner_regression_run_immediate "${selected_indexes[@]}" || overall=1
    else
        local -a pending=("${selected_indexes[@]}") next=()
        local attempt max_parallel index result reason repeated
        for ((attempt=1; attempt<=REG_TOTAL_ATTEMPTS && ${#pending[@]}>0; attempt++)); do
            max_parallel="$burst_max"
            if ((attempt > 1)); then
                [[ "$retry_wave_burst_max" == 'inherit' ]] || max_parallel="$retry_wave_burst_max"
                if [[ "$degraded_mode" == '1' || ( "$degraded_mode" == 'final' && "$attempt" -eq "$REG_TOTAL_ATTEMPTS" ) ]]; then max_parallel=1; fi
                local wave_delay="$retry_delay_sec"
                if [[ "$degraded_mode" == '1' || ( "$degraded_mode" == 'final' && "$attempt" -eq "$REG_TOTAL_ATTEMPTS" ) ]]; then
                    ((degraded_delay_sec > wave_delay)) && wave_delay="$degraded_delay_sec"
                fi
                ((wave_delay > 0)) && sleep "$wave_delay"
            fi
            if [[ "$log_style" == compact ]]; then
                printf '[WAVE A%03d] bursts=%s parallel=%s\n' "$attempt" "${#pending[@]}" "$max_parallel"
            else
                runner_info "Starting attempt wave A$(printf '%03d' "$attempt") bursts=${#pending[@]} parallel=$max_parallel"
            fi
            runner_regression_run_wave "$attempt" "$max_parallel" "$burst_start_gap_sec" "${pending[@]}" || true
            next=()
            for index in "${pending[@]}"; do
                local actual_attempt=$(( ${REG_PLAN_ATTEMPT_BASE[$index]:-0} + attempt ))
                result="$run_dir/bursts/${REG_PLAN_BURST[$index]}/attempt_$(printf '%03d' "$actual_attempt")/attempt.result"
                reason="$(cut -d'|' -f2 "$result" 2>/dev/null)"
                if [[ "$(cut -d'|' -f3 "$result" 2>/dev/null)" != 'PASS' ]]; then
                    overall=1
                    repeated="$(awk -F'|' -v b="${REG_PLAN_BURST[$index]}" -v r="$reason" 'NR>1 && $2==b && $6==r {n++} END {print n+0}' "$status_file")"
                    if [[ "$reason" == TOOL_FAIL && "$repeated" -ge 2 ]]; then
                        runner_error "[RETRY-BAILOUT] burst=${REG_PLAN_BURST[$index]} reason=$reason repeated=${repeated}x"
                    elif runner_reason_retryable "$reason" && [[ "$attempt" -lt "$REG_TOTAL_ATTEMPTS" ]]; then
                        runner_warn "[RETRY-QUEUE] burst=${REG_PLAN_BURST[$index]} reason=$reason next_wave=A$(printf '%03d' "$((attempt + 1))")"
                        next+=("$index")
                    fi
                fi
            done
            pending=("${next[@]}")
            ((burst_delay_sec > 0 && ${#pending[@]} > 0)) && sleep "$burst_delay_sec"
        done
    fi

    if awk -F'|' 'NR>1 {latest[$2]=$4} END {for (b in latest) if (latest[b] != "PASS") exit 1}' "$status_file"; then overall=0; else overall=1; fi
    report_start="$(date +%s)"
    report_state_file="$(mktemp "${TMPDIR:-/tmp}/dv-report.XXXXXX")" || {
        runner_error "Cannot create regression reporting state file"
        return 2
    }
    export RUNNER_REPORT_PROGRESS_FILE="$report_state_file"
    runner_report_progress_update case-summary
    if [[ "$live_mode" != quiet && "$heartbeat_sec" -gt 0 ]]; then
        runner_report_elapsed_heartbeat "$regression_start" "$report_start" "$report_state_file" "$heartbeat_sec" "$live_mode" regression \
            "tests=$selected_test_count bursts=${#selected_indexes[@]} cases=$REG_TOTAL_CASES" &
        report_heartbeat_pid=$!
    fi
    trap 'runner_report_stop_elapsed_heartbeat "${report_heartbeat_pid:-}" "${report_state_file:-}"; exit 130' INT TERM HUP
    runner_report_regression "$run_id" "$run_dir" "$manifest_file" "$status_file" "$regression_start" "$include_warnings" "$case_status_file" || report_rc=$?
    runner_report_stop_elapsed_heartbeat "$report_heartbeat_pid" "$report_state_file"
    report_heartbeat_pid=''; report_state_file=''
    unset RUNNER_REPORT_PROGRESS_FILE
    trap - INT TERM HUP
    ((report_rc == 0)) || return "$report_rc"
    printf 'status=%s\ncompleted=%s\n' "$overall" "$(date -Is)" >> "$run_dir/metadata/run.meta"
    [[ "$log_style" != compact ]] || runner_regression_print_final_heartbeat "$reported_case_file" "$regression_start" "$selected_test_count" "$REG_TOTAL_CASES"
    if ((overall == 0)); then runner_status_token PASS; printf ' REGRESSION run=%s tests=%s bursts=%s cases=%s\n' "$run_id" "$selected_test_count" "${#selected_indexes[@]}" "$REG_TOTAL_CASES"
    else runner_status_token FAIL; printf ' REGRESSION run=%s tests=%s bursts=%s cases=%s summary=%s\n' "$run_id" "$selected_test_count" "${#selected_indexes[@]}" "$REG_TOTAL_CASES" "$(runner_report_path "$run_dir/summary/regression.errors.log")"
    fi
    return "$overall"
}
