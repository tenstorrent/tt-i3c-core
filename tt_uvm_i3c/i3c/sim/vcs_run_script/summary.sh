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
# File        : summary.sh
# Description : TT UVM I3C simulation support file.
# Authors     : Duy Huynh, Dang Thai
# Date        : 2026-08-11
#
# *****************************************************************************


runner_latest_run_id() {
    local runs
    if [[ -s "$(runner_state_dir)/latest_run.txt" ]]; then
        local indexed
        indexed="$(head -n 1 "$(runner_state_dir)/latest_run.txt")"
        [[ -d "$(runner_runs_dir)/$indexed" ]] && { printf '%s\n' "$indexed"; return 0; }
    fi
    runs="$(runner_runs_dir)"; [[ -d "$runs" ]] || return 1
    find "$runs" -mindepth 1 -maxdepth 1 -type d -printf '%T@|%f\n' 2>/dev/null | sort -t'|' -k1,1nr | head -n 1 | cut -d'|' -f2-
}

runner_show_summary() {
    local run_id='' burst_id='' attempt='' show_all=0 tail_lines=120
    while (($#)); do
        case "$1" in
            --id|--run-id) run_id="$2"; shift 2 ;;
            --burst-id) burst_id="$2"; shift 2 ;;
            --attempt) attempt="$2"; shift 2 ;;
            --show) show_all=1; shift ;;
            --tail) tail_lines="$2"; shift 2 ;;
            *) runner_die "Unknown summary option: $1"; return $? ;;
        esac
    done
    [[ -n "$run_id" ]] || run_id="$(runner_latest_run_id)" || { runner_die "No run history found"; return $?; }
    local scope="$(runner_runs_dir)/$run_id"
    [[ -n "$burst_id" ]] && scope="$scope/bursts/$burst_id"
    if [[ -n "$attempt" ]]; then attempt="${attempt#A}"; printf -v attempt '%03d' "$((10#$attempt))"; scope="$scope/attempt_$attempt"; fi
    [[ -d "$scope" ]] || { runner_die "Summary scope does not exist: $scope"; return $?; }
    local file
    for file in "$scope/run.meta" "$scope/compile.meta" "$scope/manifest.tsv" "$scope/status.tsv" "$scope/case_status.tsv" \
        "$scope/summary/compile.log" "$scope/summary/compile.errors.log" \
        "$scope/summary/test.log" "$scope/summary/test.errors.log" "$scope/summary/seeds.tsv" "$scope/summary/seeds.latest.tsv" \
        "$scope/summary/regression.log" "$scope/summary/regression.errors.log" "$scope/summary/regression.latest.tsv" "$scope/summary/regression.cases.latest.tsv" \
        "$scope/summary/artifacts.tsv" "$scope/coverage_history.tsv" \
        "$scope/coverage.log" "$scope/coverage_metrics.tsv" "$scope/vdb_manifest.tsv" "$scope/rejected_vdbs.tsv" \
        "$scope/attempt.result"; do
        [[ -f "$file" ]] || continue
        printf '\n===== %s =====\n' "$file"
        if ((show_all)); then cat "$file"; else tail -n "$tail_lines" "$file"; fi
    done
}
