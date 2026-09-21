#!/usr/bin/env bash

runner_clean_path_allowed() {
    local path="$1" resolved out
    out="$(runner_out_dir)"
    resolved="$(cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path")" || return 1
    [[ "$resolved" == "$out" || "$resolved" == "$out"/* ]]
}

runner_clean_adopt_legacy_project_out() {
    local out resolved_out resolved_project
    out="$(runner_out_dir)"
    [[ -d "$out" && ! -e "$out/.dv_runner_root" ]] || return 0
    [[ -n "${DV_PROJECT_ROOT:-}" && -d "$DV_PROJECT_ROOT" && ! -L "$out" ]] || return 0
    resolved_out="$(cd "$out" 2>/dev/null && pwd -P)" || return 0
    resolved_project="$(cd "$DV_PROJECT_ROOT" 2>/dev/null && pwd -P)" || return 0
    [[ "$resolved_out" == "$resolved_project/sim/out" ]] || return 0
    printf 'generic-dv-runner\nproject=%s\n' "${DV_PROJECT_NAME:-unconfigured}" > "$out/.dv_runner_root"
    runner_info "Initialized output sentinel for legacy project output: $out"
}

runner_clean_project_generated_artifacts() {
    local project_root out resolved_project resolved_out path
    project_root="${DV_PROJECT_ROOT:-$RUNNER_ROOT}"
    [[ -d "$project_root" ]] || return 0
    resolved_project="$(cd "$project_root" 2>/dev/null && pwd -P)" || return 0
    out="$(runner_out_dir)"
    resolved_out="$(cd "$out" 2>/dev/null && pwd -P)" || resolved_out="$out"

    while IFS= read -r -d '' path; do
        local resolved
        resolved="$(cd "$(dirname "$path")" 2>/dev/null && pwd -P)/$(basename "$path")" || return 1
        [[ "$resolved" == "$resolved_project"/* ]] || {
            runner_error "Refusing to remove generated artifact outside project root: $path"
            return 2
        }
        [[ "$(basename "$resolved")" == '.fsm.sch.verilog.xml' ]] || {
            runner_error "Refusing unexpected project artifact: $path"
            return 2
        }
        if [[ "${RUNNER_CLEAN_DRY_RUN:-0}" == 1 ]]; then
            [[ "${RUNNER_CLEAN_SHOW_OUTPUT:-0}" != 1 ]] || runner_info "Dry-run: preserve viewer-metadata path=$resolved"
        else
            [[ "${RUNNER_CLEAN_SHOW_OUTPUT:-0}" != 1 ]] || runner_info "Remove viewer-metadata path=$resolved"
            rm -f -- "$resolved" || return $?
        fi
        RUNNER_CLEAN_ITEM_COUNT=$(( ${RUNNER_CLEAN_ITEM_COUNT:-0} + 1 ))
    done < <(
        find "$resolved_project" \
            \( -path "$resolved_out" -o -path "$resolved_out/*" -o -path '*/.git' \) -prune -o \
            -type f -name '.fsm.sch.verilog.xml' -print0 2>/dev/null
    )
}

runner_clean_elapsed_heartbeat() {
    local start="$1" label="$2" path="$3" interval="$4" show_output="${5:-0}"
    local spinner_chars='|/-\' spinner_index=0 spinner elapsed hours minutes seconds elapsed_text sleep_pid=''

    trap '[[ -z "${sleep_pid:-}" ]] || kill "$sleep_pid" 2>/dev/null || true; exit 0' INT TERM HUP
    while :; do
        sleep "$interval" &
        sleep_pid=$!
        wait "$sleep_pid" || return 0
        sleep_pid=''
        elapsed=$(( $(date +%s) - start ))
        hours=$((elapsed / 3600))
        minutes=$(((elapsed % 3600) / 60))
        seconds=$((elapsed % 60))
        printf -v elapsed_text '%02d:%02d:%02d' "$hours" "$minutes" "$seconds"
        spinner="${spinner_chars:$spinner_index:1}"
        spinner_index=$(((spinner_index + 1) % 4))
        if [[ "$show_output" != 1 && -t 1 && "${TERM:-dumb}" != dumb ]]; then
            printf '\r\033[2K[CLEAN] [%s] phase=%s elapsed=%s path=%s' "$spinner" "$label" "$elapsed_text" "$path"
        else
            printf '[CLEAN] [%s] phase=%s elapsed=%s path=%s\n' "$spinner" "$label" "$elapsed_text" "$path"
        fi
    done
}

runner_clean_stop_elapsed_heartbeat() {
    local heartbeat_pid="${1:-}"
    [[ -n "$heartbeat_pid" ]] || return 0
    kill "$heartbeat_pid" 2>/dev/null || true
    wait "$heartbeat_pid" 2>/dev/null || true
    if [[ -t 1 && "${TERM:-dumb}" != dumb ]]; then
        printf '\r\033[2K'
    fi
}

runner_clean_remove_path() {
    local path="$1" label="${2:-artifact}"
    [[ -e "$path" || -L "$path" ]] || return 0
    runner_require_managed_out_dir || return $?
    runner_clean_path_allowed "$path" || { runner_error "Refusing to remove path outside output root: $path"; return 2; }
    local rc
    if [[ "${RUNNER_CLEAN_DRY_RUN:-0}" == "1" ]]; then
        [[ "${RUNNER_CLEAN_SHOW_OUTPUT:-0}" != 1 ]] || runner_info "Dry-run: preserve $label path=$path"
        RUNNER_CLEAN_ITEM_COUNT=$(( ${RUNNER_CLEAN_ITEM_COUNT:-0} + 1 ))
        return 0
    fi

    [[ "${RUNNER_CLEAN_SHOW_OUTPUT:-0}" != 1 ]] || runner_info "Remove $label path=$path"
    rm -rf -- "$path"
    rc=$?

    if ((rc != 0)); then
        runner_error "Remove $label failed path=$path rc=$rc"
        return "$rc"
    fi
    RUNNER_CLEAN_ITEM_COUNT=$(( ${RUNNER_CLEAN_ITEM_COUNT:-0} + 1 ))
}

runner_clean_find_remove() {
    local root="$1" mode="$2"
    [[ -d "$root" ]] || return 0
    local path
    case "$mode" in
        build)
            while IFS= read -r -d '' path; do runner_clean_remove_path "$path" build || return $?; done < <(
                find "$root" -depth \( -type d \( -name build -o -name _build -o -name csrc -o -name simv.daidir \
                    -o -name DVEfiles -o -name AN.DB -o -name run_work -o -name cov_merged -o -name '*.vdb' \
                    -o -name verdiLog -o -name .wave_cache -o -name vcd2fsdbLog \) \
                    -o -type f \( -name 'simv*' -o -name ucli.key -o -name 'novas*' -o -name 'vcd2fsdb*.log' \) \) -print0 2>/dev/null)
            ;;
        dump)
            while IFS= read -r -d '' path; do runner_clean_remove_path "$path" dump || return $?; done < <(
                find "$root" -depth \( -type f \( -name '*.fsdb' -o -name '*.vcd' -o -name '*.vpd' \) \
                    -o -type d \( -name .wave_cache -o -name verdiLog -o -name vcd2fsdbLog \) \) -print0 2>/dev/null)
            ;;
        cov)
            while IFS= read -r -d '' path; do runner_clean_remove_path "$path" coverage || return $?; done < <(
                find "$root" -depth \( -type d \( -name coverage -o -name cov_report -o -name cov_merged -o -name '*.vdb' \) \
                    -o -type f \( -name '*.ucdb' -o -name '*.vdb' \) \) -print0 2>/dev/null)
            ;;
        log)
            while IFS= read -r -d '' path; do runner_clean_remove_path "$path" log || return $?; done < <(
                find "$root" -depth -type d \( -name logs -o -name log_dir -o -name log_total -o -name summary \) -print0 2>/dev/null)
            ;;
        view)
            runner_clean_remove_path "$root" viewer
            ;;
    esac
}

runner_clean_registry_rows() {
    local run_filter="$1" burst_filter="$2" test_filter="$3" seed_filter="$4" pid_filter="$5"
    local registry pid started label log_file run_id burst_id test_name seed host scheduler job_id job_state job_name command_file
    registry="$(runner_job_registry)"; [[ -f "$registry" ]] || return 0
    while IFS='|' read -r pid started label log_file run_id burst_id test_name seed host scheduler job_id job_state job_name command_file; do
        kill -0 "$pid" 2>/dev/null || continue
        [[ -z "$run_filter" || "$run_id" == "$run_filter" ]] || continue
        [[ -z "$burst_filter" || "$burst_id" == "$burst_filter" ]] || continue
        [[ -z "$test_filter" || "$test_name" == "$test_filter" ]] || continue
        [[ -z "$seed_filter" || "$seed" == "$seed_filter" ]] || continue
        [[ -z "$pid_filter" || "$pid" == "$pid_filter" ]] || continue
        printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "$pid" "$started" "$label" "$log_file" "$run_id" "$burst_id" "$test_name" "$seed" "$host" "$scheduler" "$job_id" "$job_state" "$job_name" "$command_file"
    done < "$registry"
}

runner_clean_active() {
    local rows="$1"
    [[ -n "$rows" ]] || { runner_info "No matching active jobs"; return 0; }
    local pid started label log_file run_id burst_id test_name seed host scheduler job_id job_state job_name command_file
    while IFS='|' read -r pid started label log_file run_id burst_id test_name seed host scheduler job_id job_state job_name command_file; do
        printf 'RUNNING pid=%s scheduler=%s job=%s state=%s run=%s burst=%s test=%s seed=%s label=%s log=%s\n' \
            "$pid" "${scheduler:-local}" "${job_id:--}" "${job_state:-UNKNOWN}" "${run_id:--}" "${burst_id:--}" "${test_name:--}" "${seed:--}" "$label" "$log_file"
    done <<< "$rows"
}

runner_clean_kill() {
    local rows="$1" force="$2"
    [[ -n "$rows" ]] || { runner_info "No matching active jobs"; return 0; }
    local pid started label log_file run_id burst_id test_name seed host scheduler job_id job_state job_name command_file signal='TERM'
    ((force)) && signal='KILL'
    while IFS='|' read -r pid started label log_file run_id burst_id test_name seed host scheduler job_id job_state job_name command_file; do
        [[ "${RUNNER_CLEAN_SHOW_OUTPUT:-0}" != 1 ]] || runner_warn "Sending $signal to managed pid=$pid"
        runner_scheduler_cancel "${scheduler:-local}" "$job_id" clean
        kill "-$signal" "$pid" 2>/dev/null || kill -s "$signal" "$pid" 2>/dev/null || true
        ((force)) || { sleep 1; kill -KILL "$pid" 2>/dev/null || true; }
        runner_unregister_job "$pid"
        RUNNER_CLEAN_ITEM_COUNT=$(( ${RUNNER_CLEAN_ITEM_COUNT:-0} + 1 ))
    done <<< "$rows"
}

runner_clean_failed_attempts() {
    local scope="$1" status
    while IFS= read -r -d '' status; do
        while IFS= read -r path; do
            [[ -n "$path" ]] && runner_clean_remove_path "$path" failed-attempt
        done < <(awk -F'|' 'NR>1 && $4=="FAIL" {print $7}' "$status" | sort -u)
    done < <(find "$scope" -type f -name status.tsv -print0 2>/dev/null)
}

runner_clean_failed_bursts() {
    local scope="$1" status burst run_root
    while IFS= read -r -d '' status; do
        run_root="$(dirname "$status")"
        while IFS= read -r burst; do
            [[ -n "$burst" ]] && runner_clean_remove_path "$run_root/bursts/$burst" failed-burst
        done < <(awk -F'|' 'NR>1 {latest[$2]=$4} END {for(b in latest) if(latest[b]=="FAIL") print b}' "$status")
    done < <(find "$scope" -type f -name status.tsv -print0 2>/dev/null)
}

runner_clean_failed_seeds() {
    local scope="$1" summary log_file seed_dir
    while IFS= read -r -d '' summary; do
        while IFS='|' read -r _ _ status _ _ _ log_file; do
            [[ "$status" == 'FAIL' && -n "$log_file" ]] || continue
            seed_dir="$(dirname "$(dirname "$log_file")")"
            runner_clean_remove_path "$seed_dir" failed-seed
        done < "$summary"
    done < <(find "$scope" -type f -path '*/summary/seeds.latest.tsv' -print0 2>/dev/null)
}

runner_clean() (
    local action='' temp=0 all=0 dump=0 cov=0 log=0 view=0 report_only=0 error_only=0 failed_attempts=0 failed_bursts=0
    local run_id='' burst_id='' attempt='' test_name='' seed='' pid='' force=0 dry_run=0 show_output=0
    while (($#)); do
        case "$1" in
            active|kill) action="$1"; shift ;;
            --temp|--build) temp=1; shift ;;
            -a|--a|--all) all=1; shift ;;
            --dump) dump=1; shift ;;
            --cov) cov=1; shift ;;
            --log) log=1; shift ;;
            --view|--viewer) view=1; shift ;;
            --report-only) report_only=1; shift ;;
            --error) error_only=1; shift ;;
            --attempt-failed|--failed-attempts) failed_attempts=1; shift ;;
            --burst) failed_bursts=1; shift ;;
            --id|--run-id) run_id="$2"; shift 2 ;;
            --burst-id) burst_id="$2"; shift 2 ;;
            --attempt) attempt="$2"; shift 2 ;;
            --test) test_name="$2"; shift 2 ;;
            --seed) seed="$2"; shift 2 ;;
            --pid) pid="$2"; shift 2 ;;
            --force) force=1; shift ;;
            --dry-run) dry_run=1; shift ;;
            --show-output) show_output=1; shift ;;
            *) runner_die "Unknown clean option: $1"; return $? ;;
        esac
    done

    export RUNNER_CLEAN_DRY_RUN="$dry_run" RUNNER_CLEAN_SHOW_OUTPUT="$show_output"
    local out scope view_scope rows start interval heartbeat_pid='' rc=0 RUNNER_CLEAN_ITEM_COUNT=0
    out="$(runner_out_dir)"; scope="$out"
    view_scope="$out/view"
    [[ -n "$run_id" ]] && scope="$(runner_runs_dir)/$run_id"
    [[ -n "$run_id" ]] && view_scope="$out/view/coverage/$(runner_sanitize_token "$run_id")"
    [[ -n "$burst_id" ]] && scope="$scope/bursts/$burst_id"
    if [[ -n "$attempt" ]]; then
        attempt="${attempt#A}"; attempt="${attempt#attempt_}"; printf -v attempt '%03d' "$((10#$attempt))"
        scope="$scope/attempt_$attempt"
    fi
    if ((view && !temp && !all && !dump && !cov && !log && !report_only && !error_only && !failed_attempts && !failed_bursts)); then
        scope="$view_scope"
    fi

    if [[ "$action" == active ]]; then
        rows="$(runner_clean_registry_rows "$run_id" "$burst_id" "$test_name" "$seed" "$pid")"
        runner_clean_active "$rows"
        return
    fi
    if [[ "$action" == kill ]]; then
        rows="$(runner_clean_registry_rows "$run_id" "$burst_id" "$test_name" "$seed" "$pid")"
        start="$(date +%s)"
        local job_count
        job_count="$(printf '%s\n' "$rows" | awk 'NF {n++} END {print n+0}')"
        runner_info "Clean kill started scope=$scope jobs=$job_count"
        trap 'exit 130' INT TERM HUP
        runner_clean_kill "$rows" "$force" || rc=$?
        if ((rc != 0)); then
            runner_error "Clean kill failed scope=$scope jobs=$RUNNER_CLEAN_ITEM_COUNT elapsed=$(( $(date +%s) - start ))s rc=$rc"
            return "$rc"
        fi
        runner_info "Clean kill completed scope=$scope jobs=$RUNNER_CLEAN_ITEM_COUNT elapsed=$(( $(date +%s) - start ))s"
        return 0
    fi
    ((temp || all || dump || cov || log || view || report_only || error_only || failed_attempts || failed_bursts)) || {
        runner_die "clean requires an explicit action: --temp, --all, --dump, --cov, --log, --view, --report-only, --error, --attempt-failed, --burst, active, or kill"; return $?; }
    runner_clean_adopt_legacy_project_out
    [[ -e "$scope" || ((view || temp || all)) && -e "$view_scope" ]] || {
        runner_info "Clean scope does not exist: $scope"
        return 0
    }

    if ((all)); then
        rows="$(runner_clean_registry_rows "$run_id" "$burst_id" '' '' '')"
        [[ -z "$rows" ]] || { runner_error "Managed jobs are active in the requested scope; use clean active/kill first"; runner_clean_active "$rows"; return 2; }
    fi

    start="$(date +%s)"
    interval="${RUNNER_CLEAN_PROGRESS_INTERVAL:-1}"
    [[ "$interval" =~ ^[1-9][0-9]*$ ]] || interval=1
    runner_info "Clean started scope=$scope elapsed=00:00:00 heartbeat=${interval}s"
    runner_clean_elapsed_heartbeat "$start" artifacts "$scope" "$interval" "$show_output" &
    heartbeat_pid=$!
    trap 'runner_clean_stop_elapsed_heartbeat "${heartbeat_pid:-}"' EXIT
    trap 'exit 130' INT TERM HUP

    if ((all)); then
        runner_clean_remove_path "$scope" all || rc=$?
        if ((rc == 0)) && [[ "$scope" != "$out" ]]; then runner_clean_find_remove "$view_scope" view || rc=$?; fi
        if ((rc == 0)) && [[ "$scope" == "$out" ]]; then runner_clean_project_generated_artifacts || rc=$?; fi
    else
        if ((error_only && rc == 0)); then runner_clean_failed_seeds "$scope" || rc=$?; fi
        if ((failed_attempts && rc == 0)); then runner_clean_failed_attempts "$scope" || rc=$?; fi
        if ((failed_bursts && rc == 0)); then runner_clean_failed_bursts "$scope" || rc=$?; fi
        if ((temp && rc == 0)); then
            runner_clean_find_remove "$scope" build || rc=$?
            if ((rc == 0)); then runner_clean_find_remove "$view_scope" view || rc=$?; fi
            if ((rc == 0)); then runner_clean_project_generated_artifacts || rc=$?; fi
        elif ((report_only && rc == 0)); then
            runner_clean_find_remove "$scope" build || rc=$?
            if ((rc == 0)); then runner_clean_find_remove "$scope" dump || rc=$?; fi
        else
            if ((dump && rc == 0)); then runner_clean_find_remove "$scope" dump || rc=$?; fi
            if ((cov && rc == 0)); then runner_clean_find_remove "$scope" cov || rc=$?; fi
            if ((log && rc == 0)); then runner_clean_find_remove "$scope" log || rc=$?; fi
            if ((view && rc == 0)); then runner_clean_find_remove "$view_scope" view || rc=$?; fi
            if ((view && rc == 0)); then runner_clean_project_generated_artifacts || rc=$?; fi
        fi
    fi

    runner_clean_stop_elapsed_heartbeat "$heartbeat_pid"
    heartbeat_pid=''

    if ((rc != 0)); then
        runner_error "Clean failed scope=$scope items=$RUNNER_CLEAN_ITEM_COUNT elapsed=$(( $(date +%s) - start ))s rc=$rc"
        return "$rc"
    fi
    runner_info "Clean completed scope=$scope items=$RUNNER_CLEAN_ITEM_COUNT dry_run=$dry_run elapsed=$(( $(date +%s) - start ))s"
    return 0
)
