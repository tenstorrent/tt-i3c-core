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
# File        : merge_cov.sh
# Description : TT UVM I3C simulation support file.
# Authors     : Duy Huynh, Dang Thai
# Date        : 2026-08-11
#
# *****************************************************************************


runner_cov_add_database() {
    local path="$1" source="$2" seed="$3" status="$4" resolved
    [[ -d "$path" ]] || return 0
    resolved="$(readlink -f "$path" 2>/dev/null || printf '%s' "$path")"
    [[ -z "${RUNNER_COV_SEEN[$resolved]:-}" ]] || return 0
    RUNNER_COV_SEEN[$resolved]=1
    RUNNER_COV_DATABASES+=("$resolved")
    printf '%s|%s|%s|%s\n' "$resolved" "$source" "$seed" "$status" >> "$RUNNER_COV_MANIFEST"
}

runner_cov_collect_seed_summary() {
    local summary="$1" seed attempt status rc reason elapsed log_file warnings errors fatals sva_errors scoreboard_failed dump_status dump_file case_dir vdb
    [[ -f "$summary" ]] || return 0
    while IFS='|' read -r seed attempt status rc reason elapsed log_file warnings errors fatals sva_errors scoreboard_failed dump_status dump_file; do
        [[ "$status" == PASS && -n "$log_file" ]] || continue
        case_dir="$(dirname "$(dirname "$log_file")")"
        while IFS= read -r -d '' vdb; do runner_cov_add_database "$vdb" "$summary" "$seed" PASS; done < <(
            find "$case_dir/coverage" -type d -name '*.vdb' -print0 2>/dev/null)
    done < "$summary"
}

runner_cov_collect_compile_database() {
    local summary="$1" run_dir meta coverage status compile_vdb
    [[ -f "$summary" ]] || return 0
    awk -F'|' '$3=="PASS" {found=1; exit} END {exit !found}' "$summary" || return 0
    run_dir="$(dirname "$(dirname "$summary")")"
    meta="$run_dir/compile.meta"
    [[ -f "$meta" ]] || return 0
    coverage="$(awk -F= '$1=="coverage" {print substr($0, index($0, "=")+1); exit}' "$meta")"
    status="$(awk -F= '$1=="status" {print substr($0, index($0, "=")+1); exit}' "$meta")"
    [[ "$coverage" == 1 && "$status" == 0 ]] || return 0
    compile_vdb="$(awk -F= '$1=="compile_vdb" {print substr($0, index($0, "=")+1); exit}' "$meta")"
    [[ -n "$compile_vdb" ]] || compile_vdb="$run_dir/coverage/compile.vdb"
    if [[ ! -d "$compile_vdb" ]]; then
        RUNNER_COV_MISSING_DESIGN+=("$compile_vdb|meta=$meta")
        return 0
    fi
    runner_cov_add_database "$compile_vdb" "$meta" - DESIGN
}

runner_cov_collect_pass_databases() {
    local scope="$1" manifest="$2" status_db attempt_dir summary
    RUNNER_COV_DATABASES=()
    RUNNER_COV_MANIFEST="$manifest"
    declare -gA RUNNER_COV_SEEN=()
    declare -ga RUNNER_COV_MISSING_DESIGN=()
    printf 'vdb|source_summary|seed|status\n' > "$manifest"

    while IFS= read -r -d '' status_db; do
        while IFS= read -r attempt_dir; do
            [[ -n "$attempt_dir" ]] || continue
            runner_cov_collect_compile_database "$attempt_dir/summary/seeds.latest.tsv"
            runner_cov_collect_seed_summary "$attempt_dir/summary/seeds.latest.tsv"
        done < <(awk -F'|' 'NR>1 {status[$2]=$4; dir[$2]=$7} END {for(b in status) if(status[b]=="PASS") print dir[b]}' "$status_db")
    done < <(find "$scope" -type f -name status.tsv -print0 2>/dev/null)

    while IFS= read -r -d '' summary; do
        [[ "$summary" == */bursts/* ]] && continue
        runner_cov_collect_compile_database "$summary"
        runner_cov_collect_seed_summary "$summary"
    done < <(find "$scope" -type f -path '*/summary/seeds.latest.tsv' -print0 2>/dev/null)
}

runner_cov_merge_once() {
    local scheduler="$1" cpus="$2" timeout_sec="$3" idle_timeout_sec="$4" show_output="$5"
    local output_dir="$6" log_file="$7" command_file="$8"
    shift 8
    local -a databases=("$@")
    local inputs="${databases[*]}"
    runner_build_scheduled_command "$scheduler" "$cpus" 0 0 "$RUNNER_SCRIPT_DIR/runner_make.sh" merge-cov \
        "COV_DIR=$output_dir" "COV_INPUTS=$inputs"
    runner_write_command_file "$command_file" "${RUNNER_COMMAND[@]}"
    RUNNER_ACTIVE_COMMAND_FILE="$command_file"
    RUNNER_LIVE_PHASE=coverage RUNNER_LIVE_ITEM="ACTION=merge VDBS=${#databases[@]}" \
        runner_execute_logged merge-cov "$log_file" "$timeout_sec" "$idle_timeout_sec" "$show_output" "${RUNNER_COMMAND[@]}"
}

runner_cov_validate_metrics() {
    local output_dir="$1" required_csv="$2" metrics_file
    local metric
    metrics_file="$output_dir/coverage_metrics.tsv"
    [[ -n "$required_csv" ]] || return 0
    runner_coverage_parse_metrics "$output_dir/report" "$metrics_file" || {
        runner_error "Coverage report does not contain a readable metric summary: $output_dir/report"
        return 1
    }
    required_csv="${required_csv// /}"
    while IFS= read -r metric; do
        [[ -n "$metric" ]] || continue
        metric="${metric,,}"
        [[ "$metric" == tgl ]] && metric=toggle
        grep -Fq "${metric}|" "$metrics_file" || {
            runner_error "Required coverage metric is missing: metric=$metric report=$output_dir/report"
            return 1
        }
    done < <(printf '%s\n' "$required_csv" | tr ',' '\n')
}

runner_merge_coverage() {
    local scheduler="${DV_DEFAULT_SCHEDULER:-auto}" cpus=1
    local timeout_sec="${DV_COV_MERGE_TIMEOUT_SEC:-0}" idle_timeout_sec="${DV_COV_MERGE_IDLE_TIMEOUT_SEC:-0}" show_output=0
    local scope='' run_id='' output_dir='' include_unmanaged=0 isolate_bad=1 allow_rejected=0
    local required_metrics="${DV_REQUIRED_COVERAGE_METRICS:-}"
    while (($#)); do
        case "$1" in
            --scheduler) scheduler="$2"; shift 2 ;;
            --cpus) cpus="$2"; shift 2 ;;
            --timeout) timeout_sec="$2"; shift 2 ;;
            --idle-timeout) idle_timeout_sec="$2"; shift 2 ;;
            --show-output) show_output=1; shift ;;
            --scope) scope="$2"; shift 2 ;;
            --id|--run-id) run_id="$2"; shift 2 ;;
            --output-dir) output_dir="$2"; shift 2 ;;
            --include-unmanaged) include_unmanaged=1; shift ;;
            --no-isolate-bad-vdb) isolate_bad=0; shift ;;
            --allow-rejected-vdb) allow_rejected=1; shift ;;
            --require-metrics) required_metrics="$2"; shift 2 ;;
            *) runner_die "Unknown merge-cov option: $1"; return $? ;;
        esac
    done
    scheduler="$(runner_resolve_scheduler "$scheduler")" || return $?
    runner_prepare_out_dir
    [[ -n "$scope" ]] || { if [[ -n "$run_id" ]]; then scope="$(runner_runs_dir)/$run_id"; else scope="$(runner_runs_dir)"; fi; }
    [[ "$scope" == /* ]] || scope="$RUNNER_ROOT/$scope"
    [[ -n "$output_dir" ]] || output_dir="$(runner_out_dir)/coverage/${run_id:-all}"
    mkdir -p "$output_dir" "$output_dir/logs" "$output_dir/commands"

    local manifest="$output_dir/vdb_manifest.tsv" vdb
    declare -a RUNNER_COV_DATABASES=()
    runner_cov_collect_pass_databases "$scope" "$manifest"
    if ((include_unmanaged)); then
        while IFS= read -r -d '' vdb; do runner_cov_add_database "$vdb" unmanaged - PASS; done < <(find "$scope" -type d -name '*.vdb' -print0 2>/dev/null)
    fi
    if ((${#RUNNER_COV_DATABASES[@]} == 0)) && [[ "${DRY_RUN:-0}" != 1 ]]; then
        runner_die "No latest-PASS coverage databases found under $scope; use --include-unmanaged only for reviewed external VDBs"
        return $?
    fi
    if ((${#RUNNER_COV_MISSING_DESIGN[@]} > 0)) && [[ "${DRY_RUN:-0}" != 1 ]]; then
        printf '%s\n' "${RUNNER_COV_MISSING_DESIGN[@]}" > "$output_dir/missing_design_vdbs.tsv"
        runner_die "Missing ${#RUNNER_COV_MISSING_DESIGN[@]} compile-time design VDB(s); rerun coverage compile before merging"
        return $?
    fi
    if ((${#RUNNER_COV_DATABASES[@]} == 0)); then RUNNER_COV_DATABASES=("$scope/dry_run.vdb"); fi

    runner_panel_begin "Coverage Merge Plan"
    runner_panel_value Scope "$scope"
    runner_panel_value "Selected VDBs" "${#RUNNER_COV_DATABASES[@]}"
    runner_panel_value "Selection Policy" "latest PASS attempts only"
    runner_panel_value "Isolate Bad VDB" "$isolate_bad"
    runner_panel_value Manifest "$manifest"
    runner_panel_value Output "$output_dir"
    runner_panel_end

    RUNNER_ACTIVE_RUN_ID="${run_id:-coverage_merge}"
    RUNNER_ACTIVE_TEST='coverage-merge'
    local log_file="$output_dir/logs/merge.log" command_file="$output_dir/commands/merge.sh" rc=0
    local -a rejected=()
    runner_cov_merge_once "$scheduler" "$cpus" "$timeout_sec" "$idle_timeout_sec" "$show_output" \
        "$output_dir" "$log_file" "$command_file" "${RUNNER_COV_DATABASES[@]}" || rc=$?

    if ((rc != 0 && isolate_bad == 1 && ${#RUNNER_COV_DATABASES[@]} > 1 && ${DRY_RUN:-0} != 1)); then
        runner_warn "Coverage merge failed; probing databases individually"
        local -a valid=()
        local index=0 probe_dir probe_log probe_cmd probe_rc
        for vdb in "${RUNNER_COV_DATABASES[@]}"; do
            index=$((index + 1)); probe_dir="$output_dir/probes/P$(printf '%03d' "$index")"
            mkdir -p "$probe_dir/logs" "$probe_dir/commands"
            probe_log="$probe_dir/logs/probe.log"; probe_cmd="$probe_dir/commands/probe.sh"; probe_rc=0
            RUNNER_REPORT_QUIET=1 runner_cov_merge_once "$scheduler" "$cpus" "$timeout_sec" "$idle_timeout_sec" 0 \
                "$probe_dir" "$probe_log" "$probe_cmd" "$vdb" || probe_rc=$?
            if ((probe_rc == 0)); then valid+=("$vdb"); else rejected+=("$vdb|rc=$probe_rc|log=$probe_log"); fi
        done
        if ((${#valid[@]} == ${#RUNNER_COV_DATABASES[@]})); then
            local -a compatible=() candidate_set=()
            local compat_index=0 compat_dir compat_rc
            for vdb in "${valid[@]}"; do
                candidate_set=("${compatible[@]}" "$vdb")
                if ((${#candidate_set[@]} == 1)); then compatible+=("$vdb"); continue; fi
                compat_index=$((compat_index + 1)); compat_dir="$output_dir/compat/C$(printf '%03d' "$compat_index")"
                mkdir -p "$compat_dir/logs" "$compat_dir/commands"; compat_rc=0
                RUNNER_REPORT_QUIET=1 runner_cov_merge_once "$scheduler" "$cpus" "$timeout_sec" "$idle_timeout_sec" 0 \
                    "$compat_dir" "$compat_dir/logs/compat.log" "$compat_dir/commands/compat.sh" "${candidate_set[@]}" || compat_rc=$?
                if ((compat_rc == 0)); then compatible+=("$vdb")
                else rejected+=("$vdb|rc=$compat_rc|reason=INCOMPATIBLE_VDB|log=$compat_dir/logs/compat.log")
                fi
            done
            valid=("${compatible[@]}")
        fi
        : > "$output_dir/rejected_vdbs.tsv"
        ((${#rejected[@]} == 0)) || printf '%s\n' "${rejected[@]}" > "$output_dir/rejected_vdbs.tsv"
        if ((${#valid[@]} > 0)); then
            runner_warn "Retrying merge with valid_vdb=${#valid[@]} rejected_vdb=${#rejected[@]}"
            rc=0
            runner_cov_merge_once "$scheduler" "$cpus" "$timeout_sec" "$idle_timeout_sec" "$show_output" \
                "$output_dir" "$output_dir/logs/merge.retry.log" "$output_dir/commands/merge.retry.sh" "${valid[@]}" || rc=$?
        fi
    fi

    if ((rc == 0 && ${#rejected[@]} > 0 && allow_rejected == 0)); then
        runner_error "Coverage merge rejected ${#rejected[@]} VDB(s); refusing an incomplete PASS without --allow-rejected-vdb"
        rc=1
    fi
    if ((rc == 0)) && ! runner_cov_validate_metrics "$output_dir" "$required_metrics"; then
        rc=1
    fi

    if ((rc == 0)); then runner_report_coverage "$output_dir" PASS
    else runner_report_coverage "$output_dir" FAIL
    fi
    ((rc == 0)) || runner_tail_failure "$log_file"
    return "$rc"
}
