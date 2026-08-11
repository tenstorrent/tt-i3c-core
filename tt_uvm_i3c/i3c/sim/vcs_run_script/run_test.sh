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
# File        : run_test.sh
# Description : TT UVM I3C simulation support file.
# Authors     : Duy Huynh, Dang Thai
# Date        : 2026-08-11
#
# *****************************************************************************


runner_append_seed_summary() {
    local line="$1" lock_file="${TEST_SUMMARY_FILE}.lock"
    if command -v flock >/dev/null 2>&1; then
        { flock 9; printf '%s\n' "$line" >> "$TEST_SUMMARY_FILE"; } 9>"$lock_file"
    else
        printf '%s\n' "$line" >> "$TEST_SUMMARY_FILE"
    fi
}

runner_test_compact_enabled() {
    [[ "${TEST_LOG_STYLE:-compact}" == compact ]]
}

runner_test_seed_position() {
    local target="$1" seed position=0
    runner_split_csv "$TEST_SEEDS_CSV"
    for seed in "${RUNNER_SPLIT_RESULT[@]}"; do
        position=$((position + 1))
        [[ "$seed" == "$target" ]] && { printf '%s\n' "$position"; return; }
    done
    printf '0\n'
}

runner_test_print_final_heartbeat() {
    local start_epoch="$1" total="$2" counts passed failed
    counts="$(awk -F'|' 'NR>1 {latest[$1]=$3} END {for (seed in latest) {if (latest[seed]=="PASS") p++; else if (latest[seed]=="FAIL") f++} print p+0"|"f+0}' "$TEST_SUMMARY_FILE")"
    passed="${counts%%|*}"; failed="${counts#*|}"
    printf '[HEARTBEAT] PHASE=complete SCOPE=test elapsed=%s test=%s seeds=%s pass=%s fail=%s\n' \
        "$(runner_format_duration "$(( $(date +%s) - start_epoch ))")" "$TEST_NAME" "$total" "$passed" "$failed"
}

runner_run_test_seed() {
    local seed="$1" attempt=0 rc=1 reason='' start elapsed log_file clean_log command_file label status case_dir case_cov_dir case_dump_dir case_work_dir combined_plusargs expected_dump_file dump_status dump_status_file seed_position
    seed_position="$(runner_test_seed_position "$seed")"
    ((seed_position > 0)) || seed_position=1
    while (( attempt < TEST_SEED_MAX_ATTEMPTS )); do
        attempt=$((attempt + 1))
        start="$(date +%s)"
        label="${TEST_NAME}.seed_${seed}"
        case_dir="$TEST_RUN_DIR/cases/$TEST_NAME/seed_$seed/attempt_$(printf '%03d' "$attempt")"
        case_cov_dir="$case_dir/coverage"
        case_dump_dir="$case_dir/dumps"
        case_work_dir="$case_dir/run_work"
        expected_dump_file="$case_dump_dir/${TEST_NAME}_seed_${seed}_attempt_${attempt}.${TEST_DUMP_FORMAT}"
        dump_status_file="$case_dump_dir/dump.status"
        dump_status=DISABLED
        log_file="$case_dir/logs/sim.log"
        clean_log="$case_dir/logs/sim.clean.log"
        command_file="$case_dir/command.sh"
        mkdir -p "$(dirname "$log_file")" "$case_cov_dir" "$case_dump_dir" "$case_work_dir"
        runner_project_pre_run "$TEST_NAME" "$seed" "$case_dir" || return $?
        combined_plusargs="$TEST_PLUSARGS"
        [[ -n "${DV_PROJECT_RUN_PLUSARGS:-}" ]] && combined_plusargs="${combined_plusargs:+$combined_plusargs }$DV_PROJECT_RUN_PLUSARGS"

        RUNNER_ACTIVE_RUN_ID="$TEST_RUN_ID"
        RUNNER_ACTIVE_BURST_ID="$TEST_BURST_ID"
        RUNNER_ACTIVE_TEST="$TEST_NAME"
        RUNNER_ACTIVE_SEED="$seed"
        runner_build_scheduled_command "$TEST_SCHEDULER" "$TEST_CPUS" 0 0 \
            "$RUNNER_SCRIPT_DIR/runner_make.sh" run "TEST=$TEST_NAME" "SEED=$seed" "COV=$TEST_COV" \
            "ATTEMPT=$attempt" "BUILD_DIR=$TEST_BUILD_DIR" "LOG_DIR=$case_dir/logs" "COV_DIR=$case_cov_dir" \
            "DUMP_DIR=$case_dump_dir" "RUN_WORK_DIR=$case_work_dir" "DUMP_FORMAT=$TEST_DUMP_FORMAT" \
            "UVM_VERBOSITY=$TEST_VERBOSITY" "CONFIG_DB_TRACE=$TEST_CONN" \
            "PLUSARGS=$combined_plusargs" "EXTRA_RUN_OPTS=$TEST_EXTRA_RUN_OPTS"
        runner_write_command_file "$command_file" "${RUNNER_COMMAND[@]}"
        RUNNER_ACTIVE_COMMAND_FILE="$command_file"
        if ! runner_test_compact_enabled; then
            runner_info "Run test=$TEST_NAME seed=$seed attempt=$attempt/$TEST_SEED_MAX_ATTEMPTS run=$TEST_RUN_ID"
        fi
        local worker_live_mode="${RUNNER_LIVE_MODE:-auto}"
        [[ "${TEST_PARENT_LIVE:-0}" == 1 ]] && RUNNER_LIVE_MODE=quiet
        RUNNER_LIVE_PHASE=run RUNNER_LIVE_ITEM="TEST=$TEST_NAME SEED=$seed ATTEMPT=A$(printf '%03d' "$attempt")" \
            runner_execute_logged "$label" "$log_file" "$TEST_TIMEOUT_SEC" "$TEST_IDLE_TIMEOUT_SEC" \
                "$TEST_SHOW_OUTPUT" "${RUNNER_COMMAND[@]}"
        rc=$?
        if [[ "$TEST_DUMP_FORMAT" != none && "${DRY_RUN:-0}" != 1 ]]; then
            if [[ -s "$expected_dump_file" ]]; then
                dump_status=CREATED
                runner_test_compact_enabled || runner_info "Wave dump created: $expected_dump_file"
            else
                dump_status=MISSING
                runner_warn "Wave dump missing: requested_format=$TEST_DUMP_FORMAT expected_file=$expected_dump_file"
            fi
        elif [[ "${DRY_RUN:-0}" == 1 && "$TEST_DUMP_FORMAT" != none ]]; then
            dump_status=DRY_RUN
        fi
        printf 'format=%s\nstatus=%s\nfile=%s\n' \
            "$TEST_DUMP_FORMAT" "$dump_status" "$expected_dump_file" > "$dump_status_file"
        runner_strip_ansi_log "$log_file" "$clean_log"
        RUNNER_LIVE_MODE="$worker_live_mode"
        runner_project_post_run "$TEST_NAME" "$seed" "$case_dir" "$rc" || rc=$?
        if ((rc == 0)) && runner_log_has_functional_failure "$log_file" "$TEST_INCLUDE_WARNINGS"; then
            rc=1
        fi
        if ((rc == 0)) && [[ "${DRY_RUN:-0}" != "1" && "${DV_REQUIRE_UVM_SUMMARY:-1}" == "1" ]] && ! runner_log_has_completion "$log_file"; then
            runner_warn "Completion marker is missing: test=$TEST_NAME seed=$seed"
            rc=3
        fi
        reason="$(runner_failure_reason "$rc" "$log_file")"
        runner_collect_log_metrics "$log_file"
        elapsed=$(( $(date +%s) - start ))
        ((rc == 0)) && status=PASS || status=FAIL
        runner_append_seed_summary "$seed|$(printf 'A%03d' "$attempt")|$status|$rc|$reason|$elapsed|$log_file|$RUNNER_METRIC_UVM_WARNING|$RUNNER_METRIC_UVM_ERROR|$RUNNER_METRIC_UVM_FATAL|$RUNNER_METRIC_SVA_ERROR|$RUNNER_METRIC_SCOREBOARD_FAILED|$dump_status|$expected_dump_file"
        RUNNER_SEED_DURATION_SEC="$elapsed"
        runner_report_seed_result "$status" "$TEST_NAME" "$seed" "$attempt" "$rc" "$reason" "$log_file" \
            "$RUNNER_METRIC_UVM_WARNING" "$RUNNER_METRIC_UVM_ERROR" "$RUNNER_METRIC_UVM_FATAL" "$RUNNER_METRIC_SVA_ERROR" "$RUNNER_METRIC_SCOREBOARD_FAILED" \
            "$dump_status" "$expected_dump_file" "$seed_position" "$TEST_TOTAL_SEEDS"
        unset RUNNER_SEED_DURATION_SEC
        runner_test_compact_enabled || runner_attempt_history_line "$label" "$attempt" "$rc" "$log_file"
        ((rc == 0)) && return 0
        if (( attempt >= TEST_SEED_MAX_ATTEMPTS )) || ! runner_retryable_failure "$rc" "$log_file"; then
            if [[ "$reason" == ASSERT_FAIL ]]; then
                runner_error "Assertion failure(s) from $log_file"
                runner_report_assertion_failures "$log_file" >&2
            else
                runner_tail_failure "$log_file"
            fi
            return "$rc"
        fi
        runner_warn "Retrying infrastructure failure test=$TEST_NAME seed=$seed reason=$reason"
    done
    return "$rc"
}

runner_run_test() {
    local test_name='' seed_csv='' rand_num=0 jobs=1 auto_parallel=0 extra_retry=0 seed_retry_max=1
    local scheduler="${DV_DEFAULT_SCHEDULER:-auto}" cpus=1 timeout_sec=0 idle_timeout_sec=0 show_output=0
    local compile_jobs="${DV_DEFAULT_COMPILE_JOBS:-4}"
    local plusargs="${DV_DEFAULT_PLUSARGS:-}" extra_run_opts="${DV_EXTRA_RUN_OPTS:-}" dump_format="${DV_DEFAULT_DUMP_FORMAT:-none}" cov=0 do_compile=1
    local verbosity='UVM_LOW' conn=0 include_warnings=0 run_id='' run_dir='' burst_id=''
    local build_dir='' log_dir='' cov_dir='' dump_dir='' summary_dir=''
    local heartbeat_sec=1 hang_warn_sec=150 hang_kill_sec=450 hang_pending_kill_sec=3600
    local hang_min_elapsed_sec=120 hang_low_cpu_pct=2 live_mode='auto'
    local log_style="${RUNNER_TEST_LOG_STYLE:-compact}"
    local -a explicit_seeds=()

    while (($#)); do
        case "$1" in
            -t|--test) test_name="$2"; shift 2 ;;
            -s|--seed) explicit_seeds+=("$2"); shift 2 ;;
            --seeds) seed_csv="$2"; shift 2 ;;
            -r|--rand-num) rand_num="$2"; shift 2 ;;
            -p|--parallel) auto_parallel=1; shift ;;
            --jobs|--worker) jobs="$2"; shift 2 ;;
            --retry-max) extra_retry="$2"; shift 2 ;;
            --seed-retry-max) seed_retry_max="$2"; shift 2 ;;
            --scheduler) scheduler="$2"; shift 2 ;;
            --cpus) cpus="$2"; shift 2 ;;
            --timeout) timeout_sec="$2"; shift 2 ;;
            --idle-timeout) idle_timeout_sec="$2"; shift 2 ;;
            --show-output) show_output=1; shift ;;
            --include-warnings) include_warnings=1; shift ;;
            --plusargs) plusargs="$2"; shift 2 ;;
            --extra-run-opts) extra_run_opts="$2"; shift 2 ;;
            -v|--verb|--verbosity) verbosity="$2"; shift 2 ;;
            --conn) conn=1; shift ;;
            --dump) dump_format='fsdb'; shift ;;
            --dump-format) dump_format="$2"; shift 2 ;;
            --cov) cov=1; shift ;;
            --no-comp|--run-only) do_compile=0; shift ;;
            --id|--run-id) run_id="$2"; shift 2 ;;
            --run-dir) run_dir="$2"; shift 2 ;;
            --burst-id) burst_id="$2"; shift 2 ;;
            --build-dir|--build-subdir) build_dir="$2"; shift 2 ;;
            --log-dir|--log-subdir) log_dir="$2"; shift 2 ;;
            --summary-dir|--summary-subdir) summary_dir="$2"; shift 2 ;;
            --cov-dir) cov_dir="$2"; shift 2 ;;
            --dump-dir) dump_dir="$2"; shift 2 ;;
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
            --log-style) log_style="$2"; shift 2 ;;
            --compact-log) log_style='compact'; shift ;;
            --verbose-log|--show-worker-output) log_style='verbose'; shift ;;
            *) runner_die "Unknown test option: $1"; return $? ;;
        esac
    done

    [[ -n "$test_name" ]] || { runner_die "test requires -t or --test"; return $?; }
    local value
    for value in "$rand_num" "$jobs" "$extra_retry" "$seed_retry_max" "$cpus" "$compile_jobs" "$timeout_sec" "$idle_timeout_sec" \
        "$heartbeat_sec" "$hang_warn_sec" "$hang_kill_sec" "$hang_pending_kill_sec" "$hang_min_elapsed_sec"; do
        runner_require_uint option "$value" || return $?
    done
    ((jobs > 0)) || { runner_die "--jobs must be greater than zero"; return $?; }
    ((cpus > 0)) || { runner_die "--cpus must be greater than zero"; return $?; }
    ((compile_jobs > 0)) || { runner_die "DV_DEFAULT_COMPILE_JOBS must be greater than zero"; return $?; }
    case "$verbosity" in UVM_NONE|UVM_LOW|UVM_MEDIUM|UVM_HIGH|UVM_FULL|UVM_DEBUG) ;; *) runner_die "Invalid UVM verbosity: $verbosity"; return $?;; esac
    case "$live_mode" in auto|overwrite|line|quiet) ;; *) runner_die "Invalid live mode: $live_mode"; return $?;; esac
    case "$log_style" in compact|verbose) ;; *) runner_die "Invalid log style: $log_style"; return $?;; esac
    dump_format="$(runner_normalize_dump_format "$dump_format")" || return $?
    scheduler="$(runner_resolve_scheduler "$scheduler")" || return $?
    ((auto_parallel)) && jobs="$(runner_auto_jobs)"
    ((extra_retry > 0)) && seed_retry_max=$((extra_retry + 1))
    ((seed_retry_max > 0)) || seed_retry_max=1

    local -a seeds=("${explicit_seeds[@]}")
    if [[ -n "$seed_csv" ]]; then runner_split_csv "$seed_csv"; seeds+=("${RUNNER_SPLIT_RESULT[@]}"); fi
    if ((rand_num > 0)); then runner_random_seeds "$rand_num"; seeds+=("${RUNNER_RANDOM_SEEDS[@]}"); fi
    ((${#seeds[@]} > 0)) || seeds=(1)

    runner_prepare_out_dir
    [[ -n "$run_id" ]] || run_id="$(runner_new_id test)"
    [[ -n "$run_dir" ]] || run_dir="$(runner_runs_dir)/$run_id"
    [[ "$run_dir" == /* ]] || run_dir="$RUNNER_ROOT/$run_dir"
    [[ -n "$build_dir" ]] || build_dir="$run_dir/build"
    [[ -n "$log_dir" ]] || log_dir="$run_dir/logs"
    [[ -n "$summary_dir" ]] || summary_dir="$run_dir/summary"
    [[ -n "$cov_dir" ]] || cov_dir="$run_dir/coverage"
    [[ -n "$dump_dir" ]] || dump_dir="$run_dir/dumps"
    mkdir -p "$build_dir" "$log_dir" "$summary_dir" "$cov_dir" "$dump_dir"
    runner_update_latest_run "$run_id" test

    TEST_NAME="$test_name" TEST_RUN_ID="$run_id" TEST_RUN_DIR="$run_dir" TEST_BURST_ID="$burst_id"
    RUNNER_ACTIVE_RUN_ID="$run_id"; RUNNER_ACTIVE_BURST_ID="$burst_id"; RUNNER_ACTIVE_TEST="$test_name"
    TEST_SCHEDULER="$scheduler" TEST_CPUS="$cpus" TEST_TIMEOUT_SEC="$timeout_sec"
    TEST_IDLE_TIMEOUT_SEC="$idle_timeout_sec" TEST_SHOW_OUTPUT="$show_output"
    TEST_SEED_MAX_ATTEMPTS="$seed_retry_max" TEST_PLUSARGS="$plusargs"
    TEST_EXTRA_RUN_OPTS="$extra_run_opts" TEST_DUMP_FORMAT="$dump_format" TEST_COV="$cov"
    TEST_VERBOSITY="$verbosity" TEST_CONN="$conn" TEST_INCLUDE_WARNINGS="$include_warnings"
    TEST_BUILD_DIR="$build_dir" TEST_LOG_DIR="$log_dir" TEST_COV_DIR="$cov_dir" TEST_DUMP_DIR="$dump_dir"
    TEST_SUMMARY_FILE="$summary_dir/seeds.tsv"
    TEST_LOG_STYLE="$log_style" TEST_SEEDS_CSV="$(IFS=,; echo "${seeds[*]}")" TEST_TOTAL_SEEDS="${#seeds[@]}"
    export RUNNER_HEARTBEAT_SEC="$heartbeat_sec" RUNNER_HANG_WARN_SEC="$hang_warn_sec"
    export RUNNER_HANG_KILL_SEC="$hang_kill_sec" RUNNER_HANG_PENDING_KILL_SEC="$hang_pending_kill_sec"
    export RUNNER_HANG_MIN_ELAPSED_SEC="$hang_min_elapsed_sec" RUNNER_HANG_LOW_CPU_PCT="$hang_low_cpu_pct"
    export RUNNER_LIVE_MODE="$live_mode"
    RUNNER_PARENT_STATUS_FILE="$TEST_SUMMARY_FILE"; RUNNER_PARENT_STATUS_KIND=test

    local test_start compile_rc=0
    test_start="$(date +%s)"
    printf 'seed|attempt|status|rc|reason|duration_sec|log|uvm_warning|uvm_error|uvm_fatal|sva_error|scoreboard_failed|dump_status|dump_file\n' > "$TEST_SUMMARY_FILE"
    printf 'run_id=%s\nkind=test\ntest=%s\nseeds=%s\njobs=%s\nscheduler=%s\nsimulation_cpus=%s\ncompile_jobs=%s\ncompile_policy=private\ncreated=%s\n' \
        "$run_id" "$test_name" "$(IFS=,; echo "${seeds[*]}")" "$jobs" "$scheduler" "$cpus" "$compile_jobs" "$(date -Is)" > "$run_dir/run.meta"
    runner_report_test_plan "$test_name" "$(IFS=,; echo "${seeds[*]}")" "$jobs" "$scheduler" "$cpus" "$verbosity" "$cov" \
        "$dump_format" "$do_compile" "$seed_retry_max" "$run_dir" "$heartbeat_sec" "$hang_warn_sec" "$hang_kill_sec" "$plusargs"
    if runner_test_compact_enabled; then
        printf '[TEST] run=%s test=%s seeds=%s seed_workers=%s scheduler=%s cov=%s\n' \
            "$run_id" "$test_name" "$TEST_TOTAL_SEEDS" "$jobs" "$scheduler" "$cov"
        local plan_position=0
        for seed in "${seeds[@]}"; do
            plan_position=$((plan_position + 1))
            printf '[PLAN %02d/%02d] T001 level=single test=%-48s seed=%s\n' \
                "$plan_position" "$TEST_TOTAL_SEEDS" "$test_name" "$seed"
        done
        printf '%s\n' '--------------------------------------------------------------------------------'
    fi

    if ((do_compile)); then
        local -a compile_args=(--scheduler "$scheduler" --cpus "$compile_jobs" --timeout "$timeout_sec"
            --idle-timeout "$idle_timeout_sec" --run-id "$run_id" --run-dir "$run_dir"
            --build-dir "$build_dir" --log-dir "$log_dir/compile" --cov-dir "$cov_dir" --dump-dir "$dump_dir"
            --heartbeat-sec "$heartbeat_sec" --hang-warn-sec "$hang_warn_sec" --hang-kill-sec "$hang_kill_sec"
            --hang-pending-kill-sec "$hang_pending_kill_sec" --hang-min-elapsed-sec "$hang_min_elapsed_sec"
            --hang-low-cpu-pct "$hang_low_cpu_pct" --live-mode "$live_mode")
        ((show_output)) && compile_args+=(--show-output)
        ((cov)) && compile_args+=(--cov)
        compile_args+=(--dump-format "$dump_format")
        runner_run_compile "${compile_args[@]}" || compile_rc=$?
        if ((compile_rc != 0)); then
            for seed in "${seeds[@]}"; do
                runner_append_seed_summary "$seed|A000|FAIL|$compile_rc|COMPILE_FAIL|0|$log_dir/compile/compile.log|0|0|0|0|0"
            done
            printf 'status=%s\ncompleted=%s\n' "$compile_rc" "$(date -Is)" >> "$run_dir/run.meta"
            runner_report_test "$run_id" "$test_name" "$run_dir" "$TEST_SUMMARY_FILE" "$test_start" "$include_warnings"
            return "$compile_rc"
        fi
    fi

    local overall=0 seed pid completed=0 dispatched=0 total=${#seeds[@]} parent_start
    local -a active_pids=() active_seeds=()
    parent_start="$(date +%s)"
    TEST_PARENT_LIVE=0
    ((jobs > 1 && total > 1 && show_output == 0)) && TEST_PARENT_LIVE=1
    for seed in "${seeds[@]}"; do
        [[ "$seed" =~ ^[0-9]+$ ]] || { runner_error "Invalid seed: $seed"; overall=2; continue; }
        runner_run_test_seed "$seed" &
        pid=$!; active_pids+=("$pid"); active_seeds+=("$seed"); dispatched=$((dispatched + 1))
        runner_test_compact_enabled || runner_info "[DISPATCH $dispatched/$total] test=$test_name seed=$seed pid=$pid log=$run_dir/cases/$test_name/seed_$seed/attempt_001/logs/sim.log"
        if ((${#active_pids[@]} >= jobs)); then
            pid="${active_pids[0]}"
            if ((TEST_PARENT_LIVE)); then
                runner_wait_pid_with_parent_progress "$pid" "$live_mode" seeds "$parent_start" "$completed" "$total" \
                    "${#active_pids[@]}" "$((total - dispatched))" "SEED=${active_seeds[0]}" || overall=1
            else wait "$pid" || overall=1
            fi
            completed=$((completed + 1)); active_pids=("${active_pids[@]:1}"); active_seeds=("${active_seeds[@]:1}")
        fi
    done
    while ((${#active_pids[@]})); do
        pid="${active_pids[0]}"
        if ((TEST_PARENT_LIVE)); then
            runner_wait_pid_with_parent_progress "$pid" "$live_mode" seeds "$parent_start" "$completed" "$total" \
                "${#active_pids[@]}" 0 "SEED=${active_seeds[0]}" || overall=1
        else wait "$pid" || overall=1
        fi
        completed=$((completed + 1)); active_pids=("${active_pids[@]:1}"); active_seeds=("${active_seeds[@]:1}")
    done
    ((TEST_PARENT_LIVE)) && runner_live_clear "$live_mode"
    runner_test_compact_enabled && runner_test_print_final_heartbeat "$test_start" "$total"

    printf 'status=%s\ncompleted=%s\n' "$overall" "$(date -Is)" >> "$run_dir/run.meta"
    runner_report_test "$run_id" "$test_name" "$run_dir" "$TEST_SUMMARY_FILE" "$test_start" "$include_warnings"
    if runner_test_compact_enabled; then
        if ((overall == 0)); then printf '[PASS] TEST run=%s test=%s seeds=%s\n' "$run_id" "$test_name" "$TEST_TOTAL_SEEDS"
        else printf '[FAIL] TEST run=%s test=%s seeds=%s summary=%s\n' "$run_id" "$test_name" "$TEST_TOTAL_SEEDS" "$(runner_report_path "$run_dir/summary/test.errors.log")" >&2
        fi
    elif ((overall == 0)); then runner_info "PASS run=$run_id test=$test_name seeds=$(IFS=,; echo "${seeds[*]}")"
    else runner_error "FAIL run=$run_id test=$test_name seeds=$(IFS=,; echo "${seeds[*]}")"
    fi
    return "$overall"
}
