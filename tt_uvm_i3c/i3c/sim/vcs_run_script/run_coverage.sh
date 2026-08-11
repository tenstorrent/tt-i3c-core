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
# File        : run_coverage.sh
# Description : TT UVM I3C simulation support file.
# Authors     : Duy Huynh, Dang Thai
# Date        : 2026-08-11
#
# *****************************************************************************


runner_coverage_value() {
    local cov_dir="$1" metric="$2" resolver="${3:-}" value
    if [[ -f "$cov_dir/coverage_metrics.tsv" ]]; then
        value="$(awk -F'|' -v metric="$metric" '$1==metric {print $2; exit}' "$cov_dir/coverage_metrics.tsv")"
        [[ -n "$value" ]] && { printf '%s\n' "$value"; return 0; }
    fi
    if runner_coverage_parse_metrics "$cov_dir/report" "$cov_dir/coverage_metrics.tsv" 2>/dev/null; then
        value="$(awk -F'|' -v metric="$metric" '$1==metric {print $2; exit}' "$cov_dir/coverage_metrics.tsv")"
        [[ -n "$value" ]] && { printf '%s\n' "$value"; return 0; }
    fi
    if [[ -n "$resolver" ]]; then
        runner_info "Coverage metric source=project-command metric=$metric" >&2
        value="$(COV_DIR="$cov_dir" COVERAGE_METRIC="$metric" eval "$resolver" 2>/dev/null)" || return 2
        value="$(printf '%s\n' "$value" | grep -Eo '[0-9]+([.][0-9]+)?' | tail -n 1)"
        [[ -n "$value" ]] && { printf '%s\n' "$value"; return 0; }
    fi
    value="$("$RUNNER_SCRIPT_DIR/runner_make.sh" -s coverage-value "COV_DIR=$cov_dir" "COVERAGE_METRIC=$metric" 2>/dev/null)" || return 2
    value="$(printf '%s\n' "$value" | grep -Eo '[0-9]+([.][0-9]+)?' | tail -n 1)"
    [[ -n "$value" ]] || return 2
    printf '%s\n' "$value"
}

runner_coverage_meets_target() {
    awk -v value="$1" -v target="$2" 'BEGIN {exit !(value+0 >= target+0)}'
}

runner_run_coverage() {
    local no_merge=0 skip_report=0 has_test=0 test_count=0 target=0 metric='score' max_seeds=3 max_seeds_explicit=0 check_interval=1 stop_on_target=1 probe=0
    local run_id='' scheduler="${DV_DEFAULT_SCHEDULER:-auto}" cpus=1 timeout_sec=0 idle_timeout_sec=0 show_output=0 allow_miss=0
    local timeout_explicit=0 idle_timeout_explicit=0
    local log_style="${RUNNER_LOG_STYLE:-compact}" show_worker_output=0
    local -a forwarded=()
    while (($#)); do
        case "$1" in
            --no-merge|--skip-merge) no_merge=1; shift ;;
            --skip-report) skip_report=1; shift ;;
            --target|--coverage-target) target="$2"; shift 2 ;;
            --target-metric|--coverage-metric) metric="$2"; shift 2 ;;
            --max-seeds) max_seeds="$2"; max_seeds_explicit=1; shift 2 ;;
            --check-interval) check_interval="$2"; shift 2 ;;
            --stop-on-target) stop_on_target=1; shift ;;
            --no-stop-on-target) stop_on_target=0; shift ;;
            --allow-miss|--allow-coverage-miss) allow_miss=1; shift ;;
            --probe) probe=1; max_seeds=1; max_seeds_explicit=1; target=0; shift ;;
            -t|--test) test_count=$((test_count + 1)); forwarded+=("$1" "$2"); shift 2 ;;
            --id|--run-id) run_id="$2"; shift 2 ;;
            --scheduler) scheduler="$2"; forwarded+=("$1" "$2"); shift 2 ;;
            --cpus) cpus="$2"; forwarded+=("$1" "$2"); shift 2 ;;
            --timeout) timeout_sec="$2"; timeout_explicit=1; forwarded+=("$1" "$2"); shift 2 ;;
            --idle-timeout) idle_timeout_sec="$2"; idle_timeout_explicit=1; forwarded+=("$1" "$2"); shift 2 ;;
            --show-output) show_output=1; forwarded+=("$1"); shift ;;
            --show-worker-output) show_worker_output=1; log_style='verbose'; shift ;;
            --log-style) log_style="$2"; shift 2 ;;
            --compact-log) log_style='compact'; shift ;;
            --verbose-log) log_style='verbose'; shift ;;
            *) forwarded+=("$1"); shift ;;
        esac
    done
    ((test_count == 1)) && has_test=1
    [[ "$target" =~ ^[0-9]+([.][0-9]+)?$ ]] || { runner_die "Invalid coverage target: $target"; return $?; }
    case "$metric" in score|line|cond|toggle|fsm|branch|group) ;; *) runner_die "Invalid coverage metric: $metric"; return $?;; esac
    case "$log_style" in compact|verbose) ;; *) runner_die "Invalid log style: $log_style"; return $?;; esac
    [[ "$log_style" != compact ]] || show_worker_output=0
    runner_require_uint --max-seeds "$max_seeds" || return $?; runner_require_uint --check-interval "$check_interval" || return $?
    ((max_seeds > 0 && check_interval > 0)) || { runner_die "max-seeds and check-interval must be positive"; return $?; }
    if awk -v t="$target" 'BEGIN {exit !(t <= 0)}' && ((max_seeds_explicit == 0)); then
        max_seeds=1
    fi
    runner_prepare_out_dir
    [[ -n "$run_id" ]] || run_id="$(runner_new_id coverage)"
    local closure_root="$(runner_runs_dir)/$run_id" output_dir="$(runner_out_dir)/coverage/$run_id"
    mkdir -p "$closure_root/iterations" "$output_dir"
    runner_update_latest_run "$run_id" coverage
    printf 'run_id=%s\nkind=coverage\ntarget=%s\nmetric=%s\nlog_style=%s\ncreated=%s\n' "$run_id" "$target" "$metric" "$log_style" "$(date -Is)" > "$closure_root/run.meta"
    if [[ "$log_style" == verbose ]]; then
        runner_panel_begin "Coverage Execution Plan"
        runner_panel_value "Run ID" "$run_id"
        runner_panel_value Mode "$([[ $has_test -eq 1 ]] && printf single-test || printf regression)"
        runner_panel_value Target "$target"
        runner_panel_value Metric "$metric"
        runner_panel_value "Max Iterations" "$max_seeds"
        runner_panel_value "Check Interval" "$check_interval"
        runner_panel_value "Stop On Target" "$stop_on_target"
        runner_panel_value "VDB Policy" "latest PASS attempts only"
        runner_panel_value "Compile Policy" "independent compile per burst"
        runner_panel_end
    else
        printf '[COVERAGE] run=%s mode=%s metric=%s target=%s iterations=%s\n' \
            "$run_id" "$([[ $has_test -eq 1 ]] && printf single-test || printf regression)" "$metric" "$target" "$max_seeds"
    fi

    local iteration rc=0 value='' reached=0 seed coverage_status=PASS
    for ((iteration=1; iteration<=max_seeds; iteration++)); do
        local iteration_dir="$closure_root/iterations/I$(printf '%03d' "$iteration")"
        mkdir -p "$iteration_dir"
        local -a args=("${forwarded[@]}" --cov --id "$run_id" --run-dir "$iteration_dir")
        ((has_test)) || args+=(--log-style "$log_style")
        ((show_worker_output && has_test == 0)) && args+=(--show-worker-output)
        if ((iteration > 1)); then
            runner_random_seeds 1; seed="${RUNNER_RANDOM_SEEDS[0]}"; args+=(--seeds "$seed")
        fi
        if [[ "$log_style" == compact ]]; then printf '[COV-RUN %02d/%02d] execute\n' "$iteration" "$max_seeds"
        else runner_info "Coverage iteration=$iteration/$max_seeds run=$run_id"
        fi
        if ((has_test)) && [[ "$log_style" == compact && "$show_worker_output" == 0 ]]; then
            local worker_console="$iteration_dir/worker.console.log"
            RUNNER_REPORT_QUIET=1 runner_run_test "${args[@]}" > "$worker_console" 2>&1 || rc=$?
            if ((rc == 0)); then printf '[COV-PASS %02d/%02d] test iteration complete\n' "$iteration" "$max_seeds"
            else
                printf '[COV-FAIL %02d/%02d] log=%s\n' "$iteration" "$max_seeds" "$(runner_report_path "$worker_console")" >&2
                if [[ -f "$iteration_dir/summary/failure_quick_links.log" ]]; then
                    printf 'Failure Quick Links\n%s\n' '--------------------------------------------------------------------------------' >&2
                    cat "$iteration_dir/summary/failure_quick_links.log" >&2
                fi
            fi
        elif ((has_test)); then
            runner_run_test "${args[@]}" || rc=$?
        else
            runner_run_regression "${args[@]}" || rc=$?
        fi
        if ((rc != 0)); then
            runner_report_coverage "$output_dir" FAIL "$metric" not-available "$target" "$closure_root"
            return "$rc"
        fi

        if ((no_merge == 0 && (iteration % check_interval == 0 || iteration == max_seeds) )); then
            local -a merge_args=(--scope "$closure_root" --run-id "$run_id" --output-dir "$output_dir"
                --scheduler "$scheduler" --cpus "$cpus")
            ((timeout_explicit)) && merge_args+=(--timeout "$timeout_sec")
            ((idle_timeout_explicit)) && merge_args+=(--idle-timeout "$idle_timeout_sec")
            if [[ "$metric" != score ]] && awk -v t="$target" 'BEGIN {exit !(t > 0)}'; then
                merge_args+=(--require-metrics "$metric")
            fi
            ((show_output)) && merge_args+=(--show-output)
            if [[ "$log_style" == compact && "$show_worker_output" == 0 ]]; then
                local merge_console="$output_dir/merge.console.log" merge_rc=0
                printf '[COV-MERGE %02d/%02d] databases=latest-PASS\n' "$iteration" "$max_seeds"
                RUNNER_REPORT_QUIET=1 runner_merge_coverage "${merge_args[@]}" > "$merge_console" 2>&1 || merge_rc=$?
                if ((merge_rc != 0)); then
                    printf '[COV-MERGE-FAIL] log=%s\n' "$(runner_report_path "$merge_console")" >&2
                    return "$merge_rc"
                fi
            else
                RUNNER_REPORT_QUIET=1 runner_merge_coverage "${merge_args[@]}" || return $?
            fi
            if awk -v t="$target" 'BEGIN {exit !(t > 0)}'; then
                if [[ "$log_style" == verbose ]]; then
                    runner_info "Coverage metric resolver dashboard=$([[ -f "$output_dir/report/dashboard.txt" ]] && printf yes || printf no) project_command=$([[ -n "${COVERAGE_VALUE_CMD:-}" ]] && printf configured || printf missing)"
                fi
                value="$(runner_coverage_value "$output_dir" "$metric" "${COVERAGE_VALUE_CMD:-}")" || {
                    runner_die "Coverage metric was not found in URG dashboard and COVERAGE_VALUE_CMD did not provide it"; return $?; }
                printf '%s|%s|%s|%s\n' "$(date -Is)" "$iteration" "$metric" "$value" >> "$closure_root/coverage_history.tsv"
                if [[ "$log_style" == compact ]]; then printf '[COV-METRIC %02d/%02d] %s=%s target=%s\n' "$iteration" "$max_seeds" "$metric" "$value" "$target"
                else runner_info "Coverage metric=$metric value=$value target=$target"
                fi
                if runner_coverage_meets_target "$value" "$target"; then reached=1; ((stop_on_target)) && break; fi
            fi
        fi
        ((probe)) && break
    done

    if awk -v t="$target" 'BEGIN {exit !(t > 0)}' && ((reached == 0)); then
        runner_warn "Coverage target not reached: metric=$metric value=${value:-unknown} target=$target"
        if ((allow_miss)); then
            coverage_status=MISS_ALLOWED
        else
            runner_report_coverage "$output_dir" FAIL "$metric" "${value:-unknown}" "$target" "$closure_root"
            [[ "$log_style" != compact ]] || printf '[FAIL] COVERAGE run=%s %s=%s target=%s report=%s\n' \
                "$run_id" "$metric" "${value:-unknown}" "$target" "$(runner_report_path "$output_dir/report")" >&2
            return 1
        fi
    fi
    ((skip_report)) && runner_info "--skip-report requested; merge command may still produce its tool-default report"
    printf 'status=0\ncoverage_status=%s\ncompleted=%s\n' "$coverage_status" "$(date -Is)" >> "$closure_root/run.meta"
    runner_report_coverage "$output_dir" "$coverage_status" "$metric" "${value:-not-requested}" "$target" "$closure_root"
    if [[ "$log_style" == compact ]]; then
        if [[ "$coverage_status" == PASS ]]; then
            printf '[PASS] COVERAGE run=%s %s=%s target=%s report=%s\n' \
                "$run_id" "$metric" "${value:-not-requested}" "$target" "$(runner_report_path "$output_dir/report")"
        else
            printf '[MISS-ALLOWED] COVERAGE run=%s %s=%s target=%s report=%s\n' \
                "$run_id" "$metric" "${value:-unknown}" "$target" "$(runner_report_path "$output_dir/report")"
        fi
    fi
}
