#!/usr/bin/env bash

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

runner_summary_test_from_log() {
    local log_file="$1" test_name=''
    if [[ "$log_file" =~ /tests/([^/]+)/ ]]; then
        test_name="${BASH_REMATCH[1]}"
    elif [[ "$log_file" =~ /cases/([^/]+)/ ]]; then
        test_name="${BASH_REMATCH[1]}"
    fi
    printf '%s\n' "${test_name:-unknown}"
}

runner_show_failed_tests() {
    local scope="$1" database
    local timestamp burst burst_attempt test_name case_id level plusargs seed
    local seed_attempt result rc reason duration log_file remainder found=0
    local -a case_databases=() seed_databases=()

    while IFS= read -r database; do case_databases+=("$database"); done < <(
        find "$scope" -type f -path '*/summary/regression.cases.latest.tsv' -print 2>/dev/null | sort
    )
    if ((${#case_databases[@]})); then
        for database in "${case_databases[@]}"; do
            while IFS='|' read -r timestamp burst burst_attempt test_name case_id level plusargs seed \
                    seed_attempt result rc reason duration log_file remainder; do
                [[ "$result" == FAIL ]] || continue
                printf 'Test : %s\nLog  : %s\n' "$test_name" "$(runner_report_path "$log_file")"
                found=$((found + 1))
            done < "$database"
        done
    else
        while IFS= read -r database; do seed_databases+=("$database"); done < <(
            find "$scope" -type f -path '*/summary/seeds.latest.tsv' -print 2>/dev/null | sort
        )
        for database in "${seed_databases[@]}"; do
            while IFS='|' read -r seed seed_attempt result rc reason duration log_file remainder; do
                [[ "$result" == FAIL ]] || continue
                test_name="$(runner_summary_test_from_log "$log_file")"
                printf 'Test : %s\nLog  : %s\n' "$test_name" "$(runner_report_path "$log_file")"
                found=$((found + 1))
            done < "$database"
        done
    fi

    ((found > 0)) || runner_info "No failed tests found under $(runner_report_path "$scope")"
}

runner_summary_first_file() {
    local run_dir="$1" relative
    shift
    for relative in "$@"; do
        [[ -f "$run_dir/$relative" ]] || continue
        runner_report_path "$run_dir/$relative"
        return 0
    done
    printf '%s\n' '-'
}

runner_print_summary_index_entry() {
    local run_dir="$1" run_id
    local summary_file failures_file coverage_file artifacts_file
    run_id="$(basename "$run_dir")"
    summary_file="$(runner_summary_first_file "$run_dir" \
        summary/signoff.log summary/regression.log summary/test.log summary/compile.log)"
    failures_file="$(runner_summary_first_file "$run_dir" \
        summary/failures.log summary/regression.errors.log summary/test.errors.log \
        summary/compile.errors.log summary/failure_quick_links.log)"
    coverage_file="$(runner_summary_first_file "$run_dir" summary/coverage.log)"
    artifacts_file="$(runner_summary_first_file "$run_dir" summary/artifacts.tsv)"

    printf 'Run ID: %s\n' "$run_id"
    printf '\tSummary  : %s\n' "$summary_file"
    printf '\tFailures : %s\n' "$failures_file"
    printf '\tCoverage : %s\n' "$coverage_file"
    printf '\tArtifacts: %s\n' "$artifacts_file"
}

runner_list_summary_indexes() {
    local run_id="$1" limit="$2" runs_dir run_dir count=0
    runs_dir="$(runner_runs_dir)"
    [[ -d "$runs_dir" ]] || { runner_die "No run history found"; return $?; }

    if [[ -n "$run_id" ]]; then
        run_dir="$runs_dir/$run_id"
        [[ -d "$run_dir" ]] || { runner_die "Summary run does not exist: $run_id"; return $?; }
        runner_print_summary_index_entry "$run_dir"
        return 0
    fi

    while IFS='|' read -r _ run_dir; do
        ((count == 0)) || printf '\n'
        runner_print_summary_index_entry "$run_dir"
        count=$((count + 1))
        ((count >= limit)) && break
    done < <(find "$runs_dir" -mindepth 1 -maxdepth 1 -type d -printf '%T@|%p\n' 2>/dev/null |
        sort -t'|' -k1,1nr)
    ((count > 0)) || { runner_die "No run history found"; return $?; }
}

runner_show_summary() {
    local run_id='' burst_id='' attempt='' show_all=0 fail_only=0 html_only=0 detail_mode=0
    local tail_lines=120 limit=10
    while (($#)); do
        case "$1" in
            --id|--run-id) (($# >= 2)) || { runner_die "$1 requires a value"; return $?; }; run_id="$2"; shift 2 ;;
            --burst-id) (($# >= 2)) || { runner_die "--burst-id requires a value"; return $?; }; burst_id="$2"; detail_mode=1; shift 2 ;;
            --attempt) (($# >= 2)) || { runner_die "--attempt requires a value"; return $?; }; attempt="$2"; detail_mode=1; shift 2 ;;
            --show) show_all=1; detail_mode=1; shift ;;
            --fail|--failures) fail_only=1; shift ;;
            --html) html_only=1; detail_mode=1; shift ;;
            --tail) (($# >= 2)) || { runner_die "--tail requires a value"; return $?; }; tail_lines="$2"; detail_mode=1; shift 2 ;;
            --limit) (($# >= 2)) || { runner_die "--limit requires a value"; return $?; }; limit="$2"; shift 2 ;;
            *) runner_die "Unknown summary option: $1"; return $? ;;
        esac
    done
    [[ "$limit" =~ ^[1-9][0-9]*$ ]] || { runner_die "--limit must be a positive integer"; return $?; }
    [[ "$tail_lines" =~ ^[1-9][0-9]*$ ]] || { runner_die "--tail must be a positive integer"; return $?; }
    if ((detail_mode == 0 && fail_only == 0)); then
        runner_list_summary_indexes "$run_id" "$limit"
        return $?
    fi
    [[ -n "$run_id" ]] || run_id="$(runner_latest_run_id)" || { runner_die "No run history found"; return $?; }
    local scope="$(runner_runs_dir)/$run_id"
    [[ -n "$burst_id" ]] && scope="$scope/bursts/$burst_id"
    if [[ -n "$attempt" ]]; then attempt="${attempt#A}"; printf -v attempt '%03d' "$((10#$attempt))"; scope="$scope/attempt_$attempt"; fi
    [[ -d "$scope" ]] || { runner_die "Summary scope does not exist: $scope"; return $?; }
    if ((html_only)); then
        local html_file="$scope/summary/run_summary.html"
        [[ -f "$html_file" ]] || runner_publish_html_summary "$scope"
        [[ -f "$html_file" ]] || { runner_die "HTML summary is unavailable: $run_id"; return $?; }
        printf 'HTML Summary: %s\n' "$(runner_report_path "$html_file")"
        return 0
    fi
    if ((fail_only)); then
        runner_show_failed_tests "$scope"
        return $?
    fi
    local file
    for file in "$scope/metadata/run.meta" "$scope/metadata/compile.meta" "$scope/metadata/testplan.snapshot.dv" \
        "$scope/metadata/commands/compile.sh" \
        "$scope/run.meta" "$scope/compile.meta" "$scope/testplan.snapshot.dv" \
        "$scope/metadata/manifest.tsv" "$scope/metadata/status.tsv" "$scope/metadata/case_status.tsv" \
        "$scope/manifest.tsv" "$scope/status.tsv" "$scope/case_status.tsv" \
        "$scope/summary/compile.log" "$scope/summary/compile.errors.log" \
        "$scope/summary/test.log" "$scope/summary/test.errors.log" "$scope/summary/seeds.tsv" "$scope/summary/seeds.latest.tsv" \
        "$scope/summary/regression.log" "$scope/summary/regression.errors.log" "$scope/summary/regression.latest.tsv" "$scope/summary/regression.cases.latest.tsv" \
        "$scope/summary/artifacts.tsv" "$scope/summary/coverage.log" "$scope/coverage_history.tsv" \
        "$scope/coverage.log" "$scope/coverage_metrics.tsv" "$scope/vdb_manifest.tsv" "$scope/rejected_vdbs.tsv" \
        "$scope/attempt.result"; do
        [[ -f "$file" ]] || continue
        printf '\n===== %s =====\n' "$file"
        if ((show_all)); then cat "$file"; else tail -n "$tail_lines" "$file"; fi
    done
}
