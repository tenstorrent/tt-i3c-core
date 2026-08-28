#!/usr/bin/env bash

runner_run_compile() {
    local scheduler="${DV_DEFAULT_SCHEDULER:-auto}" cpus="${DV_DEFAULT_COMPILE_JOBS:-4}" timeout_sec=0 idle_timeout_sec=0 show_output=0 cov=0
    local dump_format="${DV_DEFAULT_DUMP_FORMAT:-none}"
    local run_id='' run_dir='' build_dir='' log_dir='' cov_dir='' dump_dir='' compile_cov_dir=''
    local heartbeat_sec=1 hang_warn_sec=150 hang_kill_sec=450 hang_pending_kill_sec=3600
    local hang_min_elapsed_sec=120 hang_low_cpu_pct=2 live_mode='auto'

    while (($#)); do
        case "$1" in
            --scheduler) scheduler="$2"; shift 2 ;;
            --cpus) cpus="$2"; shift 2 ;;
            --timeout) timeout_sec="$2"; shift 2 ;;
            --idle-timeout) idle_timeout_sec="$2"; shift 2 ;;
            --show-output) show_output=1; shift ;;
            --cov) cov=1; shift ;;
            --dump) dump_format='fsdb'; shift ;;
            --dump-format) dump_format="$2"; shift 2 ;;
            --run-id) run_id="$2"; shift 2 ;;
            --run-dir) run_dir="$2"; shift 2 ;;
            --build-dir|--build-subdir) build_dir="$2"; shift 2 ;;
            --log-dir|--log-subdir) log_dir="$2"; shift 2 ;;
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
            *) runner_die "Unknown comp option: $1"; return $? ;;
        esac
    done

    local value
    for value in "$cpus" "$timeout_sec" "$idle_timeout_sec" "$heartbeat_sec" "$hang_warn_sec" "$hang_kill_sec" "$hang_pending_kill_sec" "$hang_min_elapsed_sec"; do
        runner_require_uint option "$value" || return $?
    done
    case "$live_mode" in auto|overwrite|line|quiet) ;; *) runner_die "Invalid live mode: $live_mode"; return $?;; esac
    dump_format="$(runner_normalize_dump_format "$dump_format")" || return $?
    scheduler="$(runner_resolve_scheduler "$scheduler")" || return $?

    runner_prepare_out_dir
    [[ -n "$run_id" ]] || run_id="$(runner_new_id compile)"
    [[ -n "$run_dir" ]] || run_dir="$(runner_runs_dir)/$run_id"
    [[ "$run_dir" == /* ]] || run_dir="$RUNNER_ROOT/$run_dir"
    [[ -n "$build_dir" ]] || build_dir="$run_dir/build"
    [[ -n "$log_dir" ]] || log_dir="$run_dir/compile_logs"
    [[ -n "$cov_dir" ]] || cov_dir="$run_dir/coverage"
    [[ -n "$dump_dir" ]] || dump_dir="$run_dir/dumps"
    compile_cov_dir="$cov_dir/compile.vdb"
    local metadata_dir="$run_dir/metadata"
    mkdir -p "$build_dir" "$log_dir" "$cov_dir" "$metadata_dir/commands" "$run_dir/summary"
    runner_update_latest_run "$run_id" compile

    local log_file="$log_dir/compile.log" clean_log="$log_dir/compile.clean.log" compile_start command_file="$metadata_dir/commands/compile.sh"
    local lock_file="$build_dir/.compile.lock" lock_meta="$build_dir/.compile.lock.meta" lock_fd='' lock_wait_start lock_wait_sec=0
    local debug_db="$build_dir/simv.daidir" git_sha='' verdi_kdb=0
    git_sha="$(git -C "$RUNNER_ROOT" rev-parse HEAD 2>/dev/null || true)"
    [[ "$dump_format" == fsdb && "${DV_FSDB_COMPILE_STYLE:-integrated}" == integrated ]] && verdi_kdb=1
    RUNNER_ACTIVE_RUN_ID="$run_id"
    RUNNER_ACTIVE_BURST_ID="${RUNNER_ACTIVE_BURST_ID:-}"
    RUNNER_ACTIVE_TEST='compile'

    local preflight_start preflight_rc=0
    preflight_start="$(date +%s)"
    runner_project_preflight > "$log_file" 2>&1 || preflight_rc=$?
    if [[ "${DRY_RUN:-0}" != "1" && ! -r "$FILELIST" ]]; then
        printf '[ERROR] Final ordered VCS filelist is missing: %s\n' "$FILELIST" >> "$log_file"
        preflight_rc=2
    fi
    [[ ! -s "$log_file" ]] || cat "$log_file"
    if ((preflight_rc != 0)); then
        runner_strip_ansi_log "$log_file" "$clean_log"
        printf 'run_id=%s\nproject_root=%s\ntop=%s\nfilelist=%s\ncompile_work_dir=%s\nbuild_dir=%s\ndebug_db=%s\nverdi_kdb=%s\ngit_sha=%s\ncompile_log=%s\nclean_log=%s\ncommand_file=%s\nscheduler=%s\ncompile_jobs=%s\ncoverage=%s\ncompile_vdb=%s\ndump_format=%s\nstatus=%s\n' \
            "$run_id" "$RUNNER_ROOT" "$TOP" "$FILELIST" "${COMPILE_WORK_DIR:-$RUNNER_ROOT}" "$build_dir" "$debug_db" "$verdi_kdb" \
            "$git_sha" "$log_file" "$clean_log" "$command_file" "$scheduler" "$cpus" "$cov" "$compile_cov_dir" "$dump_format" "$preflight_rc" > "$metadata_dir/compile.meta"
        runner_report_compile "$run_id" "$run_dir" "$log_file" "$preflight_rc" "$preflight_start"
        return "$preflight_rc"
    fi

    runner_build_scheduled_command "$scheduler" "$cpus" 0 0 \
        "$RUNNER_SCRIPT_DIR/runner_make.sh" comp "COV=$cov" "BUILD_DIR=$build_dir" "LOG_DIR=$log_dir" \
        "COV_DIR=$cov_dir" "COMPILE_COV_DIR=$compile_cov_dir" "DUMP_DIR=$dump_dir" "DUMP_FORMAT=$dump_format" \
        "COMPILE_JOBS=$cpus"
    runner_write_command_file "$command_file" "${RUNNER_COMMAND[@]}"
    RUNNER_ACTIVE_COMMAND_FILE="$command_file"
    # UVM Library Configuration / Compile Execution Plan panels intentionally
    # suppressed to keep single-test startup output compact. The Command
    # Execution and Single Test Execution Plan panels remain the only pre-run
    # panels (see common_reporting.sh).
    if command -v flock >/dev/null 2>&1; then
        exec 9>"$lock_file"
        lock_fd=9
        lock_wait_start="$(date +%s)"
        if ! flock -n 9; then
            runner_info "Waiting for compile lock: $lock_file owner=$(tr '\n' ' ' < "$lock_meta" 2>/dev/null || printf unknown)"
            flock 9
        fi
        lock_wait_sec=$(( $(date +%s) - lock_wait_start ))
        printf 'pid=%s\nhost=%s\nrun_id=%s\nacquired=%s\n' "${BASHPID:-$$}" "$(hostname 2>/dev/null || printf unknown)" "$run_id" "$(date -Is)" > "$lock_meta"
        : # lock acquired wait=${lock_wait_sec}s (info suppressed for compact startup)
    fi
    RUNNER_HEARTBEAT_SEC="$heartbeat_sec"
    RUNNER_HANG_WARN_SEC="$hang_warn_sec"
    RUNNER_HANG_KILL_SEC="$hang_kill_sec"
    RUNNER_HANG_PENDING_KILL_SEC="$hang_pending_kill_sec"
    RUNNER_HANG_MIN_ELAPSED_SEC="$hang_min_elapsed_sec"
    RUNNER_HANG_LOW_CPU_PCT="$hang_low_cpu_pct"
    RUNNER_LIVE_MODE="$live_mode"

    compile_start="$(date +%s)"
    # "Compile run=... log=..." info suppressed for compact startup; run_id and
    # Compile metadata and logs remain under the run root for reproducibility.
    RUNNER_LIVE_PHASE=compile RUNNER_LIVE_ITEM="PROJECT=${DV_PROJECT_NAME:-unknown}" \
        runner_execute_logged compile "$log_file" "$timeout_sec" "$idle_timeout_sec" "$show_output" "${RUNNER_COMMAND[@]}"
    local rc=$?
    runner_strip_ansi_log "$log_file" "$clean_log"
    [[ -z "$lock_fd" ]] || { rm -f "$lock_meta"; flock -u "$lock_fd"; }
    printf 'run_id=%s\nproject_root=%s\ntop=%s\nfilelist=%s\ncompile_work_dir=%s\nbuild_dir=%s\ndebug_db=%s\nverdi_kdb=%s\ngit_sha=%s\ncompile_log=%s\nclean_log=%s\ncommand_file=%s\nscheduler=%s\njob_name=%s\ncompile_jobs=%s\ncoverage=%s\ncompile_vdb=%s\ndump_format=%s\nlock_wait_sec=%s\nstatus=%s\n' \
        "$run_id" "$RUNNER_ROOT" "$TOP" "$FILELIST" "${COMPILE_WORK_DIR:-$RUNNER_ROOT}" "$build_dir" "$debug_db" "$verdi_kdb" \
        "$git_sha" "$log_file" "$clean_log" "$command_file" "$scheduler" "${RUNNER_ACTIVE_JOB_NAME:-}" "$cpus" "$cov" "$compile_cov_dir" "$dump_format" "$lock_wait_sec" "$rc" > "$metadata_dir/compile.meta"
    runner_report_compile "$run_id" "$run_dir" "$log_file" "$rc" "$compile_start"
    ((rc == 0)) || runner_tail_failure "$log_file"
    return "$rc"
}
