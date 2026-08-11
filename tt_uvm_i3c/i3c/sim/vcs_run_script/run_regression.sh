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
# File        : run_regression.sh
# Description : TT UVM I3C simulation support file.
# Authors     : Duy Huynh, Dang Thai
# Date        : 2026-08-11
#
# *****************************************************************************


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

runner_regression_attempt_reason() {
    local attempt_dir="$1" rc="$2" file reason fallback='UNKNOWN'
    if ((rc == 0)); then printf 'PASS\n'; return; fi
    if [[ -f "$attempt_dir/logs/compile/compile.log" ]] &&
       ! find "$attempt_dir/cases" -type f -name 'sim.log' -print -quit 2>/dev/null | grep -q .; then
        printf 'COMPILE_FAIL\n'
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
    local summary="$attempt_dir/summary/seeds.latest.tsv" seed seed_attempt status rc reason duration log_file
    local warnings errors fatals sva_errors scoreboard_failed dump_status dump_file timestamp
    if [[ -s "$summary" ]]; then
        while IFS='|' read -r seed seed_attempt status rc reason duration log_file warnings errors fatals sva_errors scoreboard_failed dump_status dump_file; do
            timestamp="$(date -Is)"
            runner_regression_append_case_status "$timestamp|$burst_id|A$(printf '%03d' "$burst_attempt")|$test_name|$seed|$seed_attempt|$status|$rc|$reason|$duration|$log_file|${warnings:-0}|${errors:-0}|${fatals:-0}|${sva_errors:-0}|${scoreboard_failed:-0}"
        done < "$summary"
        return
    fi
    runner_split_csv "$seeds"
    for seed in "${RUNNER_SPLIT_RESULT[@]}"; do
        timestamp="$(date -Is)"
        runner_regression_append_case_status "$timestamp|$burst_id|A$(printf '%03d' "$burst_attempt")|$test_name|$seed|-|$burst_status|$burst_rc|$burst_reason|0|$attempt_dir/console.log|0|0|0|0|0"
    done
}

runner_regression_compact_enabled() {
    [[ "${REG_LOG_STYLE:-compact}" == compact && "${REG_SHOW_WORKER_OUTPUT:-0}" == 0 ]]
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

runner_regression_print_result() {
    local index="$1" attempt="$2"
    local burst_id="${REG_PLAN_BURST[$index]}" test_name="${REG_PLAN_TEST[$index]}"
    local attempt_dir result rc=1 reason=UNKNOWN status=FAIL summary seed seed_attempt seed_status seed_rc seed_reason duration log_file
    local warnings errors fatals sva_errors scoreboard_failed dump_status dump_file
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
                "${seed_reason:-$reason}" "$log_file"
        done < "$summary"
    else
        runner_split_csv "${REG_PLAN_SEEDS[$index]}"
        log_file="$attempt_dir/console.log"
        for seed in "${RUNNER_SPLIT_RESULT[@]}"; do
            runner_report_case_result FAIL "$burst_id" "$attempt" "$test_name" "$seed" "$rc" "$reason" "$log_file"
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
    local index="$1" wave_attempt="$2" attempt burst_id test_name seeds plusargs attempt_dir worker rc=0 reason status
    attempt=$(( ${REG_PLAN_ATTEMPT_BASE[$index]:-0} + wave_attempt ))
    burst_id="${REG_PLAN_BURST[$index]}"; test_name="${REG_PLAN_TEST[$index]}"
    seeds="${REG_PLAN_SEEDS[$index]}"; plusargs="${REG_PLAN_PLUSARGS[$index]}"
    attempt_dir="$REG_RUN_DIR/bursts/$burst_id/attempt_$(printf '%03d' "$attempt")"
    worker="$REG_WORKER"
    if ((wave_attempt > 1)) && [[ "$REG_RETRY_WAVE_WORKER" != 'inherit' ]]; then worker="$REG_RETRY_WAVE_WORKER"; fi
    if [[ "$REG_DEGRADED_MODE" == '1' || ( "$REG_DEGRADED_MODE" == 'final' && "$attempt" -eq "$REG_TOTAL_ATTEMPTS" ) ]]; then
        [[ "$REG_DEGRADED_WORKER" == 'inherit' ]] || worker="$REG_DEGRADED_WORKER"
    fi
    mkdir -p "$attempt_dir"

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
    ((REG_COV)) && args+=(--cov)
    ((REG_CONN)) && args+=(--conn)
    ((REG_SHOW_OUTPUT)) && args+=(--show-output)
    ((REG_INCLUDE_WARNINGS)) && args+=(--include-warnings)
    RUNNER_REPORT_QUIET=1 runner_run_test "${args[@]}" || rc=$?
    reason="$(runner_regression_attempt_reason "$attempt_dir" "$rc")"
    ((rc == 0)) && status=PASS || status=FAIL
    printf '%s|%s|%s\n' "$rc" "$reason" "$status" > "$attempt_dir/attempt.result"
    runner_regression_record_case_results "$attempt_dir" "$burst_id" "$attempt" "$test_name" "$seeds" "$status" "$rc" "$reason"
    runner_regression_append_status "$(date -Is)|$burst_id|A$(printf '%03d' "$attempt")|$status|$rc|$reason|$attempt_dir"
    return "$rc"
}

runner_regression_run_wave() {
    local attempt="$1" max_parallel="$2" start_gap="$3"
    shift 3
    local -a indexes=("$@") active_pids=() active_indexes=()
    local index pid i rc active_index gap_index overall=0 completed=0 dispatched=0 total=${#indexes[@]} parent_start actual_attempt attempt_dir console_log
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
        if ! runner_regression_compact_enabled; then
            runner_info "[DISPATCH $((dispatched + 1))/$total] burst=${REG_PLAN_BURST[$index]} attempt=A$(printf '%03d' "$actual_attempt") test=${REG_PLAN_TEST[$index]} compile=private console=$console_log"
        fi
        if runner_regression_compact_enabled; then runner_regression_attempt_worker "$index" "$attempt" > "$console_log" 2>&1 &
        else runner_regression_attempt_worker "$index" "$attempt" &
        fi
        active_pids+=("$!"); active_indexes+=("$index"); dispatched=$((dispatched + 1))
        if ((${#active_pids[@]} >= max_parallel)); then
            pid="${active_pids[0]}"
            active_index="${active_indexes[0]}"
            if ((REG_PARENT_LIVE)); then
                runner_wait_pid_with_parent_progress "$pid" "$REG_LIVE_MODE" bursts "$parent_start" "$completed" "$total" \
                    "${#active_pids[@]}" "$((total - dispatched))" "BURST=${REG_PLAN_BURST[$active_index]}" \
                    "$REG_RUN_DIR/bursts/${REG_PLAN_BURST[$active_index]}" || overall=1
            else wait "$pid" || overall=1
            fi
            completed=$((completed + 1))
            if runner_regression_compact_enabled; then
                ((REG_PARENT_LIVE)) && runner_live_clear "$REG_LIVE_MODE"
                actual_attempt=$(( ${REG_PLAN_ATTEMPT_BASE[$active_index]:-0} + attempt ))
                runner_regression_print_result "$active_index" "$actual_attempt"
            fi
            active_pids=("${active_pids[@]:1}"); active_indexes=("${active_indexes[@]:1}")
        fi
    done
    while ((${#active_pids[@]})); do
        pid="${active_pids[0]}"
        active_index="${active_indexes[0]}"
        if ((REG_PARENT_LIVE)); then
            runner_wait_pid_with_parent_progress "$pid" "$REG_LIVE_MODE" bursts "$parent_start" "$completed" "$total" \
                "${#active_pids[@]}" 0 "BURST=${REG_PLAN_BURST[$active_index]}" \
                "$REG_RUN_DIR/bursts/${REG_PLAN_BURST[$active_index]}" || overall=1
        else wait "$pid" || overall=1
        fi
        completed=$((completed + 1))
        if runner_regression_compact_enabled; then
            ((REG_PARENT_LIVE)) && runner_live_clear "$REG_LIVE_MODE"
            actual_attempt=$(( ${REG_PLAN_ATTEMPT_BASE[$active_index]:-0} + attempt ))
            runner_regression_print_result "$active_index" "$actual_attempt"
        fi
        active_pids=("${active_pids[@]:1}"); active_indexes=("${active_indexes[@]:1}")
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
    local index pid active_index gap_index overall=0 completed=0 dispatched=0 total=$# parent_start console_log
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
        if ! runner_regression_compact_enabled; then
            runner_info "[DISPATCH $((dispatched + 1))/$total] burst=${REG_PLAN_BURST[$index]} retry=immediate compile=private console=$console_log"
        fi
        if runner_regression_compact_enabled; then runner_regression_immediate_worker "$index" > "$console_log" 2>&1 &
        else runner_regression_immediate_worker "$index" &
        fi
        pids+=("$!"); active_indexes+=("$index"); dispatched=$((dispatched + 1))
        if ((${#pids[@]} >= REG_BURST_MAX)); then
            pid="${pids[0]}"
            active_index="${active_indexes[0]}"
            if ((REG_PARENT_LIVE)); then
                runner_wait_pid_with_parent_progress "$pid" "$REG_LIVE_MODE" bursts "$parent_start" "$completed" "$total" \
                    "${#pids[@]}" "$((total - dispatched))" "BURST=${REG_PLAN_BURST[$active_index]}" \
                    "$REG_RUN_DIR/bursts/${REG_PLAN_BURST[$active_index]}" || overall=1
            else wait "$pid" || overall=1
            fi
            completed=$((completed + 1))
            if runner_regression_compact_enabled; then
                ((REG_PARENT_LIVE)) && runner_live_clear "$REG_LIVE_MODE"
                runner_regression_print_result "$active_index" 0
            fi
            pids=("${pids[@]:1}"); active_indexes=("${active_indexes[@]:1}")
        fi
    done
    while ((${#pids[@]})); do
        pid="${pids[0]}"
        active_index="${active_indexes[0]}"
        if ((REG_PARENT_LIVE)); then
            runner_wait_pid_with_parent_progress "$pid" "$REG_LIVE_MODE" bursts "$parent_start" "$completed" "$total" \
                "${#pids[@]}" 0 "BURST=${REG_PLAN_BURST[$active_index]}" \
                "$REG_RUN_DIR/bursts/${REG_PLAN_BURST[$active_index]}" || overall=1
        else wait "$pid" || overall=1
        fi
        completed=$((completed + 1))
        if runner_regression_compact_enabled; then
            ((REG_PARENT_LIVE)) && runner_live_clear "$REG_LIVE_MODE"
            runner_regression_print_result "$active_index" 0
        fi
        pids=("${pids[@]:1}"); active_indexes=("${active_indexes[@]:1}")
    done
    ((REG_PARENT_LIVE)) && runner_live_clear "$REG_LIVE_MODE"
    return "$overall"
}

runner_regression_load_plan() {
    local file="$1" include_off="$2" seeds_override="$3" rand_num="$4"
    shift 4
    local -a selectors=("$@")
    local name group level enabled seed_policy seeds plusargs tags selector matched
    REG_PLAN_TEST=(); REG_PLAN_GROUP=(); REG_PLAN_SEEDS=(); REG_PLAN_PLUSARGS=(); REG_PLAN_LEVEL=(); REG_PLAN_BURST=()
    local index=0
    grep -Eq '^#[[:space:]]*DV_TESTPLAN_VERSION=1[[:space:]]*$' "$file" || {
        runner_error "Unsupported or missing DV_TESTPLAN_VERSION=1 header: $file"
        return 2
    }
    while IFS='|' read -r name group level enabled seed_policy seeds plusargs tags; do
        name="${name#${name%%[![:space:]]*}}"; name="${name%${name##*[![:space:]]}}"
        [[ -n "$name" && "${name:0:1}" != '#' ]] || continue
        enabled="${enabled:-on}"; level="${level:-medium}"
        [[ "$include_off" == 1 || "$enabled" != 'off' ]] || continue
        matched=0
        if ((${#selectors[@]} == 0)); then matched=1; fi
        for selector in "${selectors[@]}"; do
            [[ "$selector" == "test:$name" || "$selector" == "group:$group" || "$selector" == "level:$level" ]] && matched=1
        done
        ((matched)) || continue
        if [[ ",${REG_EXCLUDED_TESTS_CSV}," == *",$name,"* || ",${REG_EXCLUDED_GROUPS_CSV}," == *",$group,"* ]]; then continue; fi
        if [[ -n "$seeds_override" ]]; then
            seeds="$seeds_override"
        elif ((rand_num > 0)); then
            runner_random_seeds "$rand_num"; seeds="$(IFS=,; echo "${RUNNER_RANDOM_SEEDS[*]}")"
        else
            seeds="${seeds:-1}"
        fi
        case "${seed_policy:-all}" in
            first) seeds="${seeds%%,*}" ;;
            random-one)
                runner_split_csv "$seeds"
                seeds="${RUNNER_SPLIT_RESULT[$((RANDOM % ${#RUNNER_SPLIT_RESULT[@]}))]}"
                ;;
            all|'') ;;
            *) runner_warn "Unknown seed policy '$seed_policy' for $name; using all seeds" ;;
        esac
        index=$((index + 1))
        REG_PLAN_TEST+=("$name"); REG_PLAN_GROUP+=("$group"); REG_PLAN_SEEDS+=("$seeds")
        REG_PLAN_PLUSARGS+=("$plusargs"); REG_PLAN_LEVEL+=("$level")
        REG_PLAN_BURST+=("B$(printf '%03d' "$index")")
    done < "$file"
}

runner_regression_write_manifest() {
    local i
    printf 'burst_id|test|group|seeds|plusargs|level\n' > "$REG_MANIFEST_FILE"
    for i in "${!REG_PLAN_TEST[@]}"; do
        printf '%s|%s|%s|%s|%s|%s\n' "${REG_PLAN_BURST[$i]}" "${REG_PLAN_TEST[$i]}" \
            "${REG_PLAN_GROUP[$i]}" "${REG_PLAN_SEEDS[$i]}" "${REG_PLAN_PLUSARGS[$i]}" "${REG_PLAN_LEVEL[$i]}" >> "$REG_MANIFEST_FILE"
    done
}

runner_regression_load_manifest() {
    local file="$1" burst_id test_name group seeds plusargs level
    REG_PLAN_TEST=(); REG_PLAN_GROUP=(); REG_PLAN_SEEDS=(); REG_PLAN_PLUSARGS=(); REG_PLAN_LEVEL=(); REG_PLAN_BURST=()
    while IFS='|' read -r burst_id test_name group seeds plusargs level; do
        [[ "$burst_id" == B* ]] || continue
        REG_PLAN_BURST+=("$burst_id"); REG_PLAN_TEST+=("$test_name"); REG_PLAN_GROUP+=("$group")
        REG_PLAN_SEEDS+=("$seeds"); REG_PLAN_PLUSARGS+=("$plusargs"); REG_PLAN_LEVEL+=("$level")
    done < "$file"
}

runner_run_regression() {
    local test_file='' group_csv='' level_csv='' seeds_override='' rand_num=0 include_off=0 all=0
    local jobs=1 auto_parallel=0 burst_max=1 burst_delay_sec=30 burst_start_gap_sec=10
    local retry_max=3 retry_delay_sec=30 retry_schedule='deferred-wave' retry_wave_burst_max='inherit' retry_wave_worker='inherit'
    local degraded_mode='final' degraded_worker='inherit' degraded_delay_sec=60 seed_retry_max=3
    local scheduler="${DV_DEFAULT_SCHEDULER:-auto}" cpus=1 timeout_sec=0 idle_timeout_sec=0 show_output=0
    local dump_format='none' cov=0 conn=0 include_warnings=0 verbosity='UVM_LOW'
    local run_id='' run_dir_override='' rerun_bursts='' rerun_failed=0 list_bursts=0 case_order='test-major'
    local heartbeat_sec=1 hang_warn_sec=150 hang_kill_sec=450 hang_pending_kill_sec=3600
    local hang_min_elapsed_sec=120 hang_low_cpu_pct=2 live_mode='auto'
    local log_style="${RUNNER_LOG_STYLE:-compact}" show_worker_output=0
    local exclude_tests='' exclude_groups=''
    local -a explicit_tests=()

    while (($#)); do
        case "$1" in
            -f|--file) test_file="$2"; shift 2 ;;
            -t|--test) explicit_tests+=("$2"); shift 2 ;;
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
    case "$case_order" in test-major|seed-major) ;; *) runner_die "Invalid case order: $case_order"; return $?;; esac
    case "$log_style" in compact|verbose) ;; *) runner_die "Invalid log style: $log_style"; return $?;; esac
    [[ "$log_style" != compact ]] || show_worker_output=0
    ((auto_parallel)) && jobs="$(runner_auto_jobs)"
    scheduler="$(runner_resolve_scheduler "$scheduler")" || return $?
    dump_format="$(runner_normalize_dump_format "$dump_format")" || return $?
    [[ "$retry_wave_burst_max" == 'inherit' ]] || runner_require_uint --retry-wave-burst-max "$retry_wave_burst_max" || return $?
    [[ "$retry_wave_worker" == 'inherit' ]] || runner_require_uint --retry-wave-worker "$retry_wave_worker" || return $?
    [[ "$degraded_worker" == 'inherit' ]] || runner_require_uint --degraded-retry-worker "$degraded_worker" || return $?

    [[ -n "$test_file" ]] || test_file="$(runner_make_value print-test-list)"
    [[ "$test_file" == /* ]] || test_file="$RUNNER_ROOT/$test_file"
    [[ -r "$test_file" ]] || { runner_die "Test-list file is not readable: $test_file"; return $?; }
    runner_prepare_out_dir
    [[ -n "$run_id" ]] || run_id="$(runner_new_id regression)"
    local run_dir="${run_dir_override:-$(runner_runs_dir)/$run_id}"
    [[ "$run_dir" == /* ]] || run_dir="$RUNNER_ROOT/$run_dir"
    local manifest_file="$run_dir/manifest.tsv" status_file="$run_dir/status.tsv" case_status_file="$run_dir/case_status.tsv"
    mkdir -p "$run_dir/bursts" "$run_dir/summary"
    runner_update_latest_run "$run_id" regression
    REG_MANIFEST_FILE="$manifest_file"; REG_STATUS_FILE="$status_file"

    REG_EXCLUDED_TESTS_CSV="$exclude_tests"; REG_EXCLUDED_GROUPS_CSV="$exclude_groups"
    local -a selectors=() values=()
    local item
    for item in "${explicit_tests[@]}"; do selectors+=("test:$item"); done
    [[ -n "$group_csv" ]] && { runner_split_csv "$group_csv"; for item in "${RUNNER_SPLIT_RESULT[@]}"; do selectors+=("group:$item"); done; }
    [[ -n "$level_csv" ]] && { runner_split_csv "$level_csv"; for item in "${RUNNER_SPLIT_RESULT[@]}"; do selectors+=("level:$item"); done; }

    if [[ -f "$manifest_file" && ( $list_bursts -eq 1 || $rerun_failed -eq 1 || -n "$rerun_bursts" ) ]]; then
        runner_regression_load_manifest "$manifest_file"
    else
        runner_regression_load_plan "$test_file" "$include_off" "$seeds_override" "$rand_num" "${selectors[@]}"
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
    runner_regression_prepare_case_index "${selected_indexes[@]}"
    printf 'timestamp|burst_id|burst_attempt|test|seed|seed_attempt|status|rc|reason|duration_sec|log|uvm_warning|uvm_error|uvm_fatal|sva_error|scoreboard_failed\n' > "$case_status_file"

    REG_PLAN_ATTEMPT_BASE=()
    for value in "${!REG_PLAN_BURST[@]}"; do
        item="${REG_PLAN_BURST[$value]}"
        local latest_attempt
        latest_attempt="$(awk -F'|' -v b="$item" '$2==b {a=$3; gsub(/^A/,"",a); if(a+0>max)max=a+0} END {print max+0}' "$status_file" 2>/dev/null)"
        REG_PLAN_ATTEMPT_BASE+=("${latest_attempt:-0}")
    done

    REG_RUN_ID="$run_id" REG_RUN_DIR="$run_dir" REG_MANIFEST_FILE="$manifest_file" REG_STATUS_FILE="$status_file" REG_CASE_STATUS_FILE="$case_status_file"
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
    export REG_RUN_ID REG_RUN_DIR REG_STATUS_FILE REG_CASE_STATUS_FILE
    RUNNER_PARENT_STATUS_FILE="$case_status_file"; RUNNER_PARENT_STATUS_KIND=regression_case
    local regression_start
    regression_start="$(date +%s)"
    printf 'run_id=%s\nkind=regression\nworker=%s\nburst_max=%s\nretry_schedule=%s\nlog_style=%s\ncompile_policy=independent_per_burst\ncreated=%s\n' \
        "$run_id" "$jobs" "$burst_max" "$retry_schedule" "$log_style" "$(date -Is)" > "$run_dir/run.meta"
    if [[ "$log_style" == verbose ]]; then
        runner_report_regression_plan "$run_id" "${#selected_indexes[@]}" "$jobs" "$burst_max" "$scheduler" "$retry_schedule" \
            "$REG_TOTAL_ATTEMPTS" "$dump_format" "$cov" "$manifest_file"
        local plan_print_limit="${RUNNER_PLAN_PRINT_LIMIT:-$REG_TOTAL_CASES}" plan_position=0 seed
        for value in "${selected_indexes[@]}"; do
            runner_split_csv "${REG_PLAN_SEEDS[$value]}"
            for seed in "${RUNNER_SPLIT_RESULT[@]}"; do
                plan_position=$((plan_position + 1)); ((plan_position <= plan_print_limit)) || continue
                runner_info "[PLAN $plan_position/$REG_TOTAL_CASES] burst=${REG_PLAN_BURST[$value]} level=${REG_PLAN_LEVEL[$value]} test=${REG_PLAN_TEST[$value]} seed=$seed"
            done
        done
        ((REG_TOTAL_CASES <= plan_print_limit)) || runner_info "Regression plan display truncated: shown=$plan_print_limit total=$REG_TOTAL_CASES manifest=$manifest_file"
    else
        local compact_plan_position=0 compact_plan_limit="${RUNNER_PLAN_PRINT_LIMIT:-$REG_TOTAL_CASES}" seed
        printf '[REGRESSION] run=%s tests=%s cases=%s seed_workers=%s burst_parallel=%s scheduler=%s cov=%s\n' \
            "$run_id" "${#selected_indexes[@]}" "$REG_TOTAL_CASES" "$jobs" "$burst_max" "$scheduler" "$cov"
        for value in "${selected_indexes[@]}"; do
            runner_split_csv "${REG_PLAN_SEEDS[$value]}"
            for seed in "${RUNNER_SPLIT_RESULT[@]}"; do
                compact_plan_position=$((compact_plan_position + 1))
                ((compact_plan_position <= compact_plan_limit)) || continue
                printf '[PLAN %02d/%02d] %s level=%-6s test=%-48s seed=%s\n' \
                    "$compact_plan_position" "$REG_TOTAL_CASES" "${REG_PLAN_BURST[$value]}" \
                    "${REG_PLAN_LEVEL[$value]}" "${REG_PLAN_TEST[$value]}" "$seed"
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
    printf 'status=%s\ncompleted=%s\n' "$overall" "$(date -Is)" >> "$run_dir/run.meta"
    [[ "$log_style" != compact ]] || runner_regression_print_final_heartbeat "$case_status_file" "$regression_start" "${#selected_indexes[@]}" "$REG_TOTAL_CASES"
    runner_report_regression "$run_id" "$run_dir" "$manifest_file" "$status_file" "$regression_start" "$include_warnings" "$case_status_file"
    if ((overall == 0)); then printf '[PASS] REGRESSION run=%s tests=%s cases=%s\n' "$run_id" "${#selected_indexes[@]}" "$REG_TOTAL_CASES"
    else printf '[FAIL] REGRESSION run=%s tests=%s cases=%s summary=%s\n' "$run_id" "${#selected_indexes[@]}" "$REG_TOTAL_CASES" "$(runner_report_path "$run_dir/summary/regression.errors.log")" >&2
    fi
    return "$overall"
}
