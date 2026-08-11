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
# File        : clean.sh
# Description : TT UVM I3C simulation support file.
# Authors     : Duy Huynh, Dang Thai
# Date        : 2026-08-11
#
# *****************************************************************************


runner_clean_path_allowed() {
    local path="$1" resolved out
    out="$(runner_out_dir)"
    resolved="$(cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path")" || return 1
    [[ "$resolved" == "$out" || "$resolved" == "$out"/* ]]
}

runner_clean_remove_path() {
    local path="$1" label="${2:-artifact}"
    [[ -e "$path" || -L "$path" ]] || return 0
    runner_require_managed_out_dir || return $?
    runner_clean_path_allowed "$path" || { runner_error "Refusing to remove path outside output root: $path"; return 2; }
    local count size start
    count="$(find "$path" -mindepth 0 2>/dev/null | wc -l | tr -d ' ')"
    size="$(du -sh "$path" 2>/dev/null | awk '{print $1}')"; start="$(date +%s)"
    runner_info "Clean $label path=$path items=${count:-0} size=${size:-unknown}"
    if [[ "${RUNNER_CLEAN_DRY_RUN:-0}" == "1" ]]; then
        runner_info "Dry-run: preserved $path"
        return 0
    fi
    rm -rf -- "$path"
    runner_info "Cleaned $label elapsed=$(( $(date +%s) - start ))s"
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
        runner_warn "Sending $signal to managed pid=$pid"
        runner_scheduler_cancel "${scheduler:-local}" "$job_id"
        kill "-$signal" "$pid" 2>/dev/null || kill -s "$signal" "$pid" 2>/dev/null || true
        ((force)) || { sleep 1; kill -KILL "$pid" 2>/dev/null || true; }
        runner_unregister_job "$pid"
    done <<< "$rows"
}

runner_clean_failed_attempts() {
    local scope="$1" status
    while IFS= read -r -d '' status; do
        awk -F'|' 'NR>1 && $4=="FAIL" {print $7}' "$status" | sort -u | while IFS= read -r path; do
            [[ -n "$path" ]] && runner_clean_remove_path "$path" failed-attempt
        done
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

runner_clean() {
    local action='' temp=0 all=0 dump=0 cov=0 log=0 report_only=0 error_only=0 failed_attempts=0 failed_bursts=0
    local run_id='' burst_id='' attempt='' test_name='' seed='' pid='' force=0 dry_run=0
    while (($#)); do
        case "$1" in
            active|kill) action="$1"; shift ;;
            --temp|--build) temp=1; shift ;;
            -a|--a|--all) all=1; shift ;;
            --dump) dump=1; shift ;;
            --cov) cov=1; shift ;;
            --log) log=1; shift ;;
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
            *) runner_die "Unknown clean option: $1"; return $? ;;
        esac
    done

    export RUNNER_CLEAN_DRY_RUN="$dry_run"
    local out scope rows
    out="$(runner_out_dir)"; scope="$out"
    [[ -n "$run_id" ]] && scope="$(runner_runs_dir)/$run_id"
    [[ -n "$burst_id" ]] && scope="$scope/bursts/$burst_id"
    if [[ -n "$attempt" ]]; then
        attempt="${attempt#A}"; attempt="${attempt#attempt_}"; printf -v attempt '%03d' "$((10#$attempt))"
        scope="$scope/attempt_$attempt"
    fi

    if [[ "$action" == active || "$action" == kill ]]; then
        rows="$(runner_clean_registry_rows "$run_id" "$burst_id" "$test_name" "$seed" "$pid")"
        [[ "$action" == active ]] && runner_clean_active "$rows" || runner_clean_kill "$rows" "$force"
        return
    fi
    ((temp || all || dump || cov || log || report_only || error_only || failed_attempts || failed_bursts)) || {
        runner_die "clean requires an explicit action: --temp, --all, --dump, --cov, --log, --report-only, --error, --attempt-failed, --burst, active, or kill"; return $?; }
    [[ -e "$scope" ]] || { runner_info "Clean scope does not exist: $scope"; return 0; }

    if ((all)); then
        rows="$(runner_clean_registry_rows "$run_id" "$burst_id" '' '' '')"
        [[ -z "$rows" ]] || { runner_error "Managed jobs are active in the requested scope; use clean active/kill first"; runner_clean_active "$rows"; return 2; }
        runner_clean_remove_path "$scope" all
        return
    fi
    ((error_only)) && runner_clean_failed_seeds "$scope"
    ((failed_attempts)) && runner_clean_failed_attempts "$scope"
    ((failed_bursts)) && runner_clean_failed_bursts "$scope"
    if ((temp)); then runner_clean_find_remove "$scope" build; return; fi
    if ((report_only)); then runner_clean_find_remove "$scope" build; runner_clean_find_remove "$scope" dump; return; fi
    ((dump)) && runner_clean_find_remove "$scope" dump
    ((cov)) && runner_clean_find_remove "$scope" cov
    ((log)) && runner_clean_find_remove "$scope" log
    return 0
}
