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
# File        : common_active_jobs.sh
# Description : TT UVM I3C simulation support file.
# Authors     : Duy Huynh, Dang Thai
# Date        : 2026-08-11
#
# *****************************************************************************


runner_job_registry() {
    printf '%s\n' "${RUNNER_JOB_REGISTRY:-$(runner_state_dir)/active_jobs/jobs.tsv}"
}

runner_register_job() {
    local pid="$1" label="$2" log_file="$3" registry
    registry="$(runner_job_registry)"
    mkdir -p "$(dirname "$registry")"
    local row
    row="$(printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s' "$pid" "$(date +%s)" "$label" "$log_file" \
        "${RUNNER_ACTIVE_RUN_ID:-}" "${RUNNER_ACTIVE_BURST_ID:-}" \
        "${RUNNER_ACTIVE_TEST:-}" "${RUNNER_ACTIVE_SEED:-}" "$(hostname 2>/dev/null || printf unknown)" \
        "${RUNNER_ACTIVE_SCHEDULER:-local}" "${RUNNER_ACTIVE_JOB_ID:-}" "${RUNNER_ACTIVE_JOB_STATE:-UNKNOWN}" \
        "${RUNNER_ACTIVE_JOB_NAME:-}" "${RUNNER_ACTIVE_COMMAND_FILE:-}")"
    if command -v flock >/dev/null 2>&1; then
        { flock 9; printf '%s\n' "$row" >> "$registry"; } 9>"${registry}.lock"
    else
        printf '%s\n' "$row" >> "$registry"
    fi
}

runner_update_job_scheduler() {
    local pid="$1" scheduler="$2" job_id="$3" job_state="$4" job_name="$5" registry tmp
    registry="$(runner_job_registry)"; [[ -f "$registry" ]] || return 0
    tmp="${registry}.tmp.${BASHPID:-$$}.${RANDOM}"
    if command -v flock >/dev/null 2>&1; then
        {
            flock 9
            awk -F'|' -v OFS='|' -v pid="$pid" -v scheduler="$scheduler" -v jid="$job_id" -v state="$job_state" -v jname="$job_name" \
                '{if($1==pid){$10=scheduler;$11=jid;$12=state;$13=jname} print}' "$registry" > "$tmp" && mv -f "$tmp" "$registry"
        } 9>"${registry}.lock"
    else
        awk -F'|' -v OFS='|' -v pid="$pid" -v scheduler="$scheduler" -v jid="$job_id" -v state="$job_state" -v jname="$job_name" \
            '{if($1==pid){$10=scheduler;$11=jid;$12=state;$13=jname} print}' "$registry" > "$tmp" && mv -f "$tmp" "$registry"
    fi
}

runner_unregister_job() {
    local pid="$1" registry tmp
    registry="$(runner_job_registry)"
    [[ -f "$registry" ]] || return 0
    tmp="${registry}.tmp.${BASHPID:-$$}.${RANDOM}"
    if command -v flock >/dev/null 2>&1; then
        {
            flock 9
            [[ -f "$registry" ]] || return 0
            awk -F'|' -v pid="$pid" '$1 != pid' "$registry" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
            mv -f "$tmp" "$registry" 2>/dev/null || rm -f "$tmp"
        } 9>"${registry}.lock"
    else
        if ! awk -F'|' -v pid="$pid" '$1 != pid' "$registry" > "$tmp" 2>/dev/null; then rm -f "$tmp"; return 0; fi
        mv -f "$tmp" "$registry" 2>/dev/null || rm -f "$tmp"
    fi
}

runner_list_jobs() {
    local registry pid started label log_file run_id burst_id test_name seed host scheduler job_id job_state job_name command_file
    registry="$(runner_job_registry)"
    [[ -f "$registry" ]] || { runner_info "No registered jobs"; return 0; }
    while IFS='|' read -r pid started label log_file run_id burst_id test_name seed host scheduler job_id job_state job_name command_file; do
        [[ -n "$pid" ]] || continue
        if kill -0 "$pid" 2>/dev/null; then
            printf 'RUNNING pid=%s host=%s scheduler=%s job=%s state=%s run=%s burst=%s test=%s seed=%s label=%s log=%s\n' \
                "$pid" "${host:--}" "${scheduler:-local}" "${job_id:--}" "${job_state:-UNKNOWN}" \
                "${run_id:--}" "${burst_id:--}" "${test_name:--}" "${seed:--}" "$label" "$log_file"
        else
            runner_unregister_job "$pid"
        fi
    done < "$registry"
}

runner_stop_jobs() {
    local registry pid started label log_file run_id burst_id test_name seed host scheduler job_id job_state job_name command_file
    registry="$(runner_job_registry)"
    [[ -f "$registry" ]] || { runner_info "No registered jobs"; return 0; }
    while IFS='|' read -r pid started label log_file run_id burst_id test_name seed host scheduler job_id job_state job_name command_file; do
        [[ -n "$pid" ]] || continue
        if kill -0 "$pid" 2>/dev/null; then
            runner_warn "Stopping pid=$pid label=$label"
            runner_scheduler_cancel "${scheduler:-local}" "$job_id"
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done < "$registry"
    rm -f "$registry"
}
