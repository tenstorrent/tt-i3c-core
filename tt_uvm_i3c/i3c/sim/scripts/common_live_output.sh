#!/usr/bin/env bash

# A Slurm job that remains RUNNING without log progress is terminated after the
# configured hang window.  Set this to 0 for intentionally quiet, long jobs.
RUNNER_ALLOW_REMOTE_HANG_KILL="${RUNNER_ALLOW_REMOTE_HANG_KILL:-1}"

runner_file_size_bytes() {
    local path="$1" size=''
    [[ -f "$path" ]] || { printf '0\n'; return; }
    size="$(stat -c '%s' "$path" 2>/dev/null || true)"
    [[ "$size" =~ ^[0-9]+$ ]] || size="$(wc -c < "$path" 2>/dev/null | tr -d '[:space:]')"
    [[ "$size" =~ ^[0-9]+$ ]] || size=0
    printf '%s\n' "$size"
}

runner_format_log_size() {
    local size="${1:-0}"
    [[ "$size" =~ ^[0-9]+$ ]] || size=0
    if ((size >= 1073741824)); then printf '%dGB' "$((size / 1073741824))"
    elif ((size >= 1048576)); then printf '%dMB' "$((size / 1048576))"
    elif ((size >= 1024)); then printf '%dKB' "$((size / 1024))"
    else printf '%dB' "$size"
    fi
}

runner_format_log_size_decimal() {
    local size="${1:-0}"
    [[ "$size" =~ ^[0-9]+$ ]] || size=0
    awk -v bytes="$size" 'BEGIN {
        if (bytes >= 1073741824) printf "%.2fGB", bytes / 1073741824;
        else if (bytes >= 1048576) printf "%.2fMB", bytes / 1048576;
        else if (bytes >= 1024) printf "%.2fKB", bytes / 1024;
        else printf "%dB", bytes;
    }'
}

runner_format_duration() {
    local total="${1:-0}" days hours minutes seconds
    [[ "$total" =~ ^[0-9]+$ ]] || total=0
    days=$((total / 86400)); hours=$(((total % 86400) / 3600))
    minutes=$(((total % 3600) / 60)); seconds=$((total % 60))
    printf '%dd %02dh %02dm %02ds' "$days" "$hours" "$minutes" "$seconds"
}

runner_format_compact_duration() {
    local total="${1:-0}" days hours minutes seconds
    [[ "$total" =~ ^[0-9]+$ ]] || total=0
    days=$((total / 86400)); hours=$(((total % 86400) / 3600))
    minutes=$(((total % 3600) / 60)); seconds=$((total % 60))
    if ((days > 0)); then printf '%dd%02dh' "$days" "$hours"
    elif ((hours > 0)); then printf '%dh%02dm' "$hours" "$minutes"
    elif ((minutes > 0)); then printf '%dm%02ds' "$minutes" "$seconds"
    else printf '%ds' "$seconds"
    fi
}

runner_terminal_cols() {
    local cols="${COLUMNS:-0}"
    if ! [[ "$cols" =~ ^[0-9]+$ ]] || ((cols <= 0)); then
        cols="$(stty size < /dev/tty 2>/dev/null | awk '{print $2}')"
    fi
    [[ "$cols" =~ ^[0-9]+$ ]] && ((cols > 0)) || cols=80
    printf '%s\n' "$cols"
}

runner_fit_message() {
    local message="$1" cols max_len
    cols="$(runner_terminal_cols)"; max_len=$((cols - 1)); ((max_len >= 16)) || max_len=16
    if ((${#message} <= max_len)); then printf '%s' "$message"
    elif ((max_len <= 3)); then printf '%.*s' "$max_len" "$message"
    else printf '%.*s...' "$((max_len - 3))" "$message"
    fi
}

runner_live_open_output() {
    RUNNER_LIVE_OUTPUT_FD=''
    # Compact regression workers redirect stdout to console.log, but they still
    # own the interactive terminal.  Open it directly so hang/timeout notices
    # remain visible while ordinary worker output stays captured in the log.
    if [[ -t 1 && -e /dev/tty && -w /dev/tty ]]; then
        exec {RUNNER_LIVE_OUTPUT_FD}>/dev/tty 2>/dev/null || RUNNER_LIVE_OUTPUT_FD=''
    fi
}

runner_live_close_output() {
    if [[ -n "${RUNNER_LIVE_OUTPUT_FD:-}" ]]; then
        exec {RUNNER_LIVE_OUTPUT_FD}>&-
        RUNNER_LIVE_OUTPUT_FD=''
    fi
}

runner_live_printf() {
    local format="$1"; shift
    if [[ -n "${RUNNER_LIVE_OUTPUT_FD:-}" ]]; then printf "$format" "$@" >&${RUNNER_LIVE_OUTPUT_FD}
    else printf "$format" "$@"
    fi
}

runner_live_mode_is_overwrite() {
    local mode="$1"
    [[ "$mode" == overwrite || ( "$mode" == auto && -t 1 ) ]]
}

runner_live_clear() {
    local mode="$1"
    if runner_live_mode_is_overwrite "$mode" && [[ "${RUNNER_LIVE_LINE_ACTIVE:-0}" == 1 ]]; then
        runner_live_printf '\r\033[2K'
        RUNNER_LIVE_LINE_ACTIVE=0
    fi
}

runner_live_emit() {
    local mode="$1" message="$2" fitted
    [[ "$mode" != quiet ]] || return 0
    if runner_live_mode_is_overwrite "$mode"; then
        fitted="$(runner_fit_message "$message")"
        runner_live_printf '\r\033[2K%s' "$fitted"
        RUNNER_LIVE_LINE_ACTIVE=1
    else
        runner_live_printf '%s\n' "$message"
        RUNNER_LIVE_LINE_ACTIVE=0
    fi
}

runner_live_notice() {
    local mode="$1" message="$2"
    runner_live_clear "$mode"
    runner_live_printf '%s\n' "$message"
}

runner_process_group_cpu_pct() {
    local pid="$1" pgid
    pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | awk 'NR==1 {print $1}' | tr -d '[:space:]')"
    [[ "$pgid" =~ ^[0-9]+$ ]] || { printf '0.00\n'; return; }
    ps -eo pgid=,pcpu= 2>/dev/null | awk -v target="$pgid" '$1 == target {sum += $2} END {printf "%.2f", sum + 0}'
}

runner_cpu_is_idle() {
    awk -v current="${1:-0}" -v limit="${2:-0}" 'BEGIN {exit !((current + 0) <= (limit + 0))}'
}

runner_log_scheduler_state() {
    local file="$1"
    if grep -Eiq 'queued and waiting|pending job|waiting for resources|job .* pending|state[=:][[:space:]]*PENDING' "$file" 2>/dev/null; then
        printf 'PENDING\n'
    elif grep -Eiq 'allocated resources|has been allocated|starting on|launching task|state[=:][[:space:]]*RUNNING' "$file" 2>/dev/null; then
        printf 'RUNNING\n'
    else
        printf 'UNKNOWN\n'
    fi
}

runner_terminate_process() {
    local pid="$1" scheduler="${2:-local}" job_id="${3:-}"
    runner_scheduler_cancel "$scheduler" "$job_id"
    kill -TERM "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
    sleep 2
    kill -KILL "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
}

runner_parent_activity_snapshot() {
    local burst_root="$1" attempt_root='' compile_log='' compile_meta='' phase=dispatch size=0 file
    [[ -d "$burst_root" ]] || { printf 'dispatch|0B\n'; return; }
    attempt_root="$(find "$burst_root" -mindepth 1 -maxdepth 1 -type d -name 'attempt_*' -print 2>/dev/null | sort | tail -n 1)"
    [[ -n "$attempt_root" ]] || { printf 'dispatch|0B\n'; return; }
    compile_log="$attempt_root/compile_logs/compile.log"
    [[ -f "$compile_log" ]] || compile_log="$attempt_root/logs/compile/compile.log"
    compile_meta="$attempt_root/metadata/compile.meta"
    [[ -f "$compile_meta" ]] || compile_meta="$attempt_root/compile.meta"
    # The tests directory is the authoritative indication that execution has
    # entered the run phase.  Check it before compile.meta: the worker creates
    # run artifacts just before compile metadata becomes visible, and the old
    # ordering left a stale PHASE=compile heartbeat on that transition.
    local tests_root="$attempt_root/tests"
    [[ -d "$tests_root" ]] || tests_root="$attempt_root/cases"
    if [[ -d "$tests_root" ]]; then
        phase=run
        while IFS= read -r -d '' file; do
            size=$((size + $(runner_file_size_bytes "$file")))
        done < <(find "$tests_root" -type f -name 'sim.log' -print0 2>/dev/null)
    elif [[ ! -f "$compile_meta" ]]; then
        phase=compile
        size="$(runner_file_size_bytes "$compile_log")"
    else
        phase=setup
    fi
    printf '%s|%s\n' "$phase" "$(runner_format_log_size "$size")"
}

# Shared live-output prefix: "[TAG] [spinner] PHASE=<phase> elapsed=<elapsed>".
# Both the aggregate parent heartbeat and the per-item logger start from this
# common shape and then append their own tail (which stays deliberately
# different: done/active/queued for the parent vs log_size/slurm_job per item).
runner_live_prefix() {
    local tag="$1" spinner="$2" phase="$3" elapsed_text="$4"
    printf '[%s] [%s] PHASE=%s elapsed=%s' "$tag" "$spinner" "$phase" "$elapsed_text"
}

runner_parent_live_status() {
    local mode="$1" scope="$2" start_epoch="$3" completed="$4" total="$5" active="$6" queued="$7" oldest="${8:-}" detail_root="${9:-}"
    local now elapsed spinner_chars='|/-\' index spinner message scheduler_counts result_counts activity activity_phase='' activity_size='' display_phase=parallel
    local pending_jobs=0 running_jobs=0 pass_count=0 fail_count=0
    [[ "$mode" != quiet ]] || return 0
    now="$(date +%s)"; elapsed=$((now - start_epoch))
    index="${RUNNER_PARENT_SPINNER_INDEX:-0}"; spinner="${spinner_chars:$index:1}"
    RUNNER_PARENT_SPINNER_INDEX=$(((index + 1) % 4))
    if [[ -n "$detail_root" ]]; then
        activity="$(runner_parent_activity_snapshot "$detail_root")"
        activity_phase="${activity%%|*}"; activity_size="${activity#*|}"
        [[ "$activity_phase" == dispatch ]] || display_phase="$activity_phase"
    fi
    message="$(runner_live_prefix HEARTBEAT "$spinner" "$display_phase" "$(runner_format_duration "$elapsed")") SCOPE=$scope done=$completed/$total active=$active queued=$queued"
    if [[ -f "${RUNNER_PARENT_STATUS_FILE:-}" ]]; then
        case "${RUNNER_PARENT_STATUS_KIND:-test}" in
            regression) result_counts="$(awk -F'|' 'NR>1 {s[$2]=$4} END {for(k in s){if(s[k]=="PASS")p++; else if(s[k]=="FAIL")f++} print p+0"|"f+0}' "$RUNNER_PARENT_STATUS_FILE")" ;;
            regression_case) result_counts="$(awk -F'|' 'NR>1 {s[$2 SUBSEP $5]=$7} END {for(k in s){if(s[k]=="PASS")p++; else if(s[k]=="FAIL")f++} print p+0"|"f+0}' "$RUNNER_PARENT_STATUS_FILE")" ;;
            *) result_counts="$(awk -F'|' 'NR>1 {s[$1]=$3} END {for(k in s){if(s[k]=="PASS")p++; else if(s[k]=="FAIL")f++} print p+0"|"f+0}' "$RUNNER_PARENT_STATUS_FILE")" ;;
        esac
        pass_count="${result_counts%%|*}"; fail_count="${result_counts#*|}"
        message+=" pass=$pass_count fail=$fail_count"
    fi
    if [[ -f "$(runner_job_registry)" ]]; then
        scheduler_counts="$(awk -F'|' -v run="${RUNNER_ACTIVE_RUN_ID:-}" '$5==run {if($12 ~ /PEND|CONFIG/)p++; if($12 ~ /RUN|COMPLET/)r++} END {print p+0"|"r+0}' "$(runner_job_registry)" 2>/dev/null)"
        pending_jobs="${scheduler_counts%%|*}"; running_jobs="${scheduler_counts#*|}"
        message+=" slurm_pending=$pending_jobs slurm_running=$running_jobs"
    fi
    [[ -z "$oldest" ]] || message+=" oldest=$oldest"
    if [[ -n "$detail_root" ]]; then
        message+=" log_size=$activity_size"
    fi
    runner_live_emit "$mode" "$message"
}

runner_wait_pid_with_parent_progress() {
    local pid="$1" mode="$2" scope="$3" start_epoch="$4" completed="$5" total="$6" active="$7" queued="$8" oldest="${9:-}" detail_root="${10:-}"
    local interval="${RUNNER_HEARTBEAT_SEC:-1}" last now
    [[ "$interval" =~ ^[0-9]+$ ]] || interval=1
    last="$(date +%s)"
    runner_live_open_output || true
    while kill -0 "$pid" 2>/dev/null; do
        now="$(date +%s)"
        if ((interval > 0 && now - last >= interval)); then
            runner_parent_live_status "$mode" "$scope" "$start_epoch" "$completed" "$total" "$active" "$queued" "$oldest" "$detail_root"
            last="$now"
        fi
        sleep 1
    done
    runner_live_clear "$mode"
    runner_live_close_output
    wait "$pid"
}

runner_report_progress_update() {
    local step="$1" state_file="${RUNNER_REPORT_PROGRESS_FILE:-}"
    [[ -n "$state_file" ]] || return 0
    printf '%s\n' "$step" > "$state_file" 2>/dev/null || true
}

runner_report_elapsed_heartbeat() {
    local overall_start="$1" report_start="$2" state_file="$3" interval="$4" mode="$5" scope="$6" context="${7:-}"
    local spinner_chars='|/-\' spinner_index=0 spinner now elapsed report_elapsed step sleep_pid='' message
    [[ "$interval" =~ ^[1-9][0-9]*$ ]] || interval=1
    trap '[[ -z "${sleep_pid:-}" ]] || kill "$sleep_pid" 2>/dev/null || true; runner_live_clear "$mode"; runner_live_close_output; exit 0' INT TERM HUP
    runner_live_open_output || true
    while :; do
        sleep "$interval" &
        sleep_pid=$!
        wait "$sleep_pid" || return 0
        sleep_pid=''
        now="$(date +%s)"
        elapsed=$((now - overall_start))
        report_elapsed=$((now - report_start))
        step="$(head -n 1 "$state_file" 2>/dev/null || true)"
        step="${step:-reporting}"
        spinner="${spinner_chars:$spinner_index:1}"
        spinner_index=$(((spinner_index + 1) % 4))
        message="$(runner_live_prefix HEARTBEAT "$spinner" report "$(runner_format_duration "$elapsed")") SCOPE=$scope report_elapsed=$(runner_format_duration "$report_elapsed") step=$step${context:+ $context}"
        runner_live_emit "$mode" "$message"
    done
}

runner_report_stop_elapsed_heartbeat() {
    local heartbeat_pid="${1:-}" state_file="${2:-}"
    if [[ -n "$heartbeat_pid" ]]; then
        kill "$heartbeat_pid" 2>/dev/null || true
        wait "$heartbeat_pid" 2>/dev/null || true
    fi
    [[ -z "$state_file" ]] || rm -f "$state_file"
}

runner_execute_logged() {
    local label="$1" log_file="$2" timeout_sec="$3" idle_timeout_sec="$4" show_output="$5"
    shift 5
    local phase="${RUNNER_LIVE_PHASE:-$label}" item="${RUNNER_LIVE_ITEM:-}" live_mode="${RUNNER_LIVE_MODE:-auto}"
    local heartbeat_sec="${RUNNER_HEARTBEAT_SEC:-1}" non_tty_sec="${RUNNER_NON_TTY_HEARTBEAT_SEC:-60}"
    local hang_warn_sec="${RUNNER_HANG_WARN_SEC:-150}" hang_kill_sec="${RUNNER_HANG_KILL_SEC:-450}"
    local hang_pending_kill_sec="${RUNNER_HANG_PENDING_KILL_SEC:-3600}"
    local hang_min_elapsed_sec="${RUNNER_HANG_MIN_ELAPSED_SEC:-120}" hang_low_cpu_pct="${RUNNER_HANG_LOW_CPU_PCT:-2}"
    local start now elapsed size=0 last_size=-1 last_progress last_heartbeat=0 pid tail_pid='' rc=0
    local no_progress=0 suspect_since=0 warned=0 cpu_pct='0.00' low_cpu_note='' scheduler_state='UNKNOWN'
    local heartbeat_printed=0 effective_kill=0 elapsed_text size_human size_decimal message
    local spinner_chars='|/-\' spinner_index=0 spinner
    local scheduler="${RUNNER_ACTIVE_SCHEDULER:-local}" job_name="${RUNNER_ACTIVE_JOB_NAME:-}" job_id='' raw_job_state='' job_partition='' job_node='' job_reason='' snapshot=''

    mkdir -p "$(dirname "$log_file")"; : > "$log_file"
    start="$(date +%s)"; last_progress="$start"; RUNNER_LIVE_LINE_ACTIVE=0
    runner_live_open_output || true

    if command -v setsid >/dev/null 2>&1; then setsid "$@" >"$log_file" 2>&1 &
    else "$@" >"$log_file" 2>&1 &
    fi
    pid=$!; runner_register_job "$pid" "$label" "$log_file"
    if [[ "$show_output" == 1 ]]; then
        tail --pid="$pid" -n +1 -F "$log_file" & tail_pid=$!
    fi

    while kill -0 "$pid" 2>/dev/null; do
        sleep 1; now="$(date +%s)"; elapsed=$((now - start)); size="$(runner_file_size_bytes "$log_file")"
        if ((size != last_size)); then last_size="$size"; last_progress="$now"; suspect_since=0; warned=0
        elif ((elapsed >= hang_min_elapsed_sec)); then [[ "$suspect_since" -gt 0 ]] || suspect_since="$now"
        fi
        no_progress=$((now - last_progress)); elapsed_text="$(runner_format_duration "$elapsed")"
        size_human="$(runner_format_log_size "$size")"; size_decimal="$(runner_format_log_size_decimal "$size")"

        if [[ "$scheduler" == slurm && -n "$job_name" ]]; then
            snapshot="$(runner_scheduler_snapshot "$scheduler" "$job_name" || true)"
            if [[ -n "$snapshot" ]]; then
                IFS='|' read -r job_id raw_job_state job_partition job_node job_reason <<< "$snapshot"
                scheduler_state="$(runner_scheduler_state_class "$raw_job_state")"
                runner_update_job_scheduler "$pid" "$scheduler" "$job_id" "$raw_job_state" "$job_name"
            fi
        fi

        local interval="$heartbeat_sec"
        [[ "$live_mode" == auto && ! -t 1 && "$interval" -lt "$non_tty_sec" ]] && interval="$non_tty_sec"
        if [[ "$show_output" != 1 && "$live_mode" != quiet && "$interval" -gt 0 && $((now - last_heartbeat)) -ge "$interval" ]]; then
            spinner="${spinner_chars:$spinner_index:1}"; spinner_index=$(((spinner_index + 1) % 4))
            message="$(runner_live_prefix LIVE "$spinner" "$phase" "$elapsed_text")${item:+ $item} log_size=$size_human ($size_decimal)"
            [[ -z "$job_id" ]] || message+=" slurm_job=$job_id state=${raw_job_state:-UNKNOWN} partition=${job_partition:--} node=${job_node:--}"
            runner_live_emit "$live_mode" "$message"; heartbeat_printed=1; last_heartbeat="$now"
        fi

        if ((suspect_since > 0)); then
            local suspect=$((now - suspect_since))
            cpu_pct="$(runner_process_group_cpu_pct "$pid")"
            if runner_cpu_is_idle "$cpu_pct" "$hang_low_cpu_pct"; then low_cpu_note="low_cpu<=${hang_low_cpu_pct}%"
            else low_cpu_note="cpu_active>${hang_low_cpu_pct}%"
            fi
            if [[ "$scheduler_state" == UNKNOWN ]]; then scheduler_state="$(runner_log_scheduler_state "$log_file")"; fi
            if ((hang_warn_sec > 0 && suspect >= hang_warn_sec && warned == 0)); then
                runner_live_notice "$live_mode" "[HANG-WARN] PHASE=$phase${item:+ $item} suspect=${suspect}s no_progress=${no_progress}s cpu=${cpu_pct}% $low_cpu_note log_size=$size_human scheduler_state=$scheduler_state"
                warned=1
            fi
            effective_kill="$hang_kill_sec"
            [[ "$scheduler_state" == PENDING ]] && effective_kill="$hang_pending_kill_sec"
            if [[ "$scheduler" == slurm && "$scheduler_state" == RUNNING && "${RUNNER_ALLOW_REMOTE_HANG_KILL:-1}" != 1 ]]; then effective_kill=0; fi
            if ((effective_kill > 0 && suspect >= effective_kill)); then
                runner_live_notice "$live_mode" "[HANG-FAIL] PHASE=$phase${item:+ $item} suspect=${suspect}s no_progress=${no_progress}s cpu=${cpu_pct}% log_size=$size_human scheduler_state=$scheduler_state action=terminate"
                runner_terminate_process "$pid" "$scheduler" "$job_id"; rc=125; break
            fi
        fi

        if ((timeout_sec > 0 && elapsed >= timeout_sec)); then
            runner_live_notice "$live_mode" "[TIMEOUT] PHASE=$phase${item:+ $item} elapsed=$elapsed_text limit=${timeout_sec}s action=terminate"
            runner_terminate_process "$pid" "$scheduler" "$job_id"; rc=124; break
        fi
        if ((idle_timeout_sec > 0 && no_progress >= idle_timeout_sec)); then
            runner_live_notice "$live_mode" "[HANG-FAIL] PHASE=$phase${item:+ $item} no_progress=${no_progress}s limit=${idle_timeout_sec}s action=terminate"
            runner_terminate_process "$pid" "$scheduler" "$job_id"; rc=125; break
        fi
    done

    if ((rc == 0)); then wait "$pid" || rc=$?; else wait "$pid" 2>/dev/null || true; fi
    [[ -z "$tail_pid" ]] || wait "$tail_pid" 2>/dev/null || true
    runner_sanitize_log_in_place "$log_file" || runner_warn "Could not remove ANSI control sequences from log: $log_file"
    now="$(date +%s)"; elapsed=$((now - start)); size="$(runner_file_size_bytes "$log_file")"
    if ((heartbeat_printed)) && ! runner_live_mode_is_overwrite "$live_mode"; then
        runner_live_emit "$live_mode" "[LIVE] PHASE=$phase${item:+ $item} completed elapsed=$(runner_format_duration "$elapsed") log_size=$(runner_format_log_size "$size") ($(runner_format_log_size_decimal "$size"))"
    else runner_live_clear "$live_mode"
    fi
    runner_live_close_output; runner_unregister_job "$pid"
    return "$rc"
}
