#!/usr/bin/env bash

runner_run_signoff() {
    local target=0 allow_miss=0 coverage_seeds='' coverage_rand=0 regression_seeds='' regression_rand=0 phase_wait=0
    local metric='score' max_seeds=3 run_id='' include_cov_tests=0 apply_waiver=0
    local waiver_file="${DV_COV_WAIVER_FILE:-}" waiver_manifest="${DV_COV_WAIVER_MANIFEST:-}"
    local log_style="${RUNNER_LOG_STYLE:-compact}"
    local -a common=() regression_extra=() selection=()
    while (($#)); do
        case "$1" in
            --target|--coverage-target) target="$2"; shift 2 ;;
            --allow-miss|--allow-coverage-miss) allow_miss=1; shift ;;
            --coverage-seeds) coverage_seeds="$2"; shift 2 ;;
            --coverage-rand-num) coverage_rand="$2"; shift 2 ;;
            --regression-seeds) regression_seeds="$2"; shift 2 ;;
            --regression-rand-num) regression_rand="$2"; shift 2 ;;
            --phase-wait-sec|--inter-phase-wait-sec) phase_wait="$2"; shift 2 ;;
            --target-metric|--coverage-metric) metric="$2"; shift 2 ;;
            --max-seeds) max_seeds="$2"; shift 2 ;;
            --id|--run-id) run_id="$2"; shift 2 ;;
            --regression-exclude-label) regression_extra+=(--exclude-label "$2"); shift 2 ;;
            --regression-exclude-test) regression_extra+=(--exclude-test "$2"); shift 2 ;;
            --include-coverage-tests-in-regression) include_cov_tests=1; shift ;;
            --waiver|--apply-waivers) apply_waiver=1; shift ;;
            --waiver-file) waiver_file="$2"; apply_waiver=1; shift 2 ;;
            --waiver-manifest) waiver_manifest="$2"; apply_waiver=1; shift 2 ;;
            -t|--test|-g|--group|--label|--level)
                selection+=("$1" "$2"); shift 2 ;;
            --all|--include-off)
                selection+=("$1"); shift ;;
            --log-style)
                log_style="$2"; common+=("$1" "$2"); shift 2 ;;
            --scheduler|--cpus|--timeout|--idle-timeout|--worker|--jobs|--burst-max|--cpoint-max|--burst-jobs|--burst-delay-sec|--burst-start-gap-sec|--case-order|--attempt-retry-max|--attempt-retry-delay-sec|--retry-schedule|--retry-wave-burst-max|--retry-wave-worker|--seed-retry-max|--degraded-retry-mode|--degraded-retry-delay-sec|--degraded-retry-worker|--heartbeat-sec|--hang-warn-sec|--hang-kill-sec|--hang-pending-kill-sec|--hang-min-elapsed-sec|--hang-low-cpu-pct|--live-mode|--dump-format|--verbosity)
                common+=("$1" "$2"); shift 2 ;;
            --show-worker-output)
                log_style='verbose'; common+=("$1"); shift ;;
            --show-output|--parallel|--burst-parallel|--include-warnings|--conn|--dump|--retry-immediate|--retry-deferred-wave|--degraded-retry|--no-degraded-retry|--no-degraded-retry-clean)
                common+=("$1"); shift ;;
            --compact-log) log_style='compact'; common+=("$1"); shift ;;
            --verbose-log) log_style='verbose'; common+=("$1"); shift ;;
            *) runner_die "Unknown signoff option: $1"; return $? ;;
        esac
    done
    [[ "$target" =~ ^[0-9]+([.][0-9]+)?$ ]] || { runner_die "Invalid signoff target: $target"; return $?; }
    awk -v t="$target" 'BEGIN {exit !(t > 0)}' || { runner_die "signoff requires --target greater than zero"; return $?; }
    case "$log_style" in compact|verbose) ;; *) runner_die "Invalid log style: $log_style"; return $?;; esac
    runner_require_uint --phase-wait-sec "$phase_wait" || return $?
    [[ -n "$run_id" ]] || run_id="$(runner_new_id signoff)"
    local root="$(runner_runs_dir)/$run_id"; mkdir -p "$root/summary" "$root/metadata"
    local run_meta="$root/metadata/run.meta"
    local coverage_summary="$(runner_out_dir)/coverage/${run_id}_coverage/coverage.log"
    local regression_summary="$(runner_runs_dir)/${run_id}_regression/summary/regression.log"
    printf 'run_id=%s\nkind=signoff\ntarget=%s\nwaivers=%s\nlog_style=%s\ncreated=%s\n' \
        "$run_id" "$target" "$([[ $apply_waiver -eq 1 ]] && printf applied || printf disabled)" "$log_style" "$(date -Is)" > "$run_meta"

    ((${#selection[@]} > 0)) || selection=(--all)
    if [[ "$log_style" == compact ]]; then
        printf '[SIGNOFF] run=%s target=%s metric=%s\n' "$run_id" "$target" "$metric"
        printf '[PHASE 1/2] COVERAGE start\n'
    fi
    local -a cov_args=("${selection[@]}" --target "$target" --target-metric "$metric" --max-seeds "$max_seeds" --id "${run_id}_coverage" "${common[@]}")
    [[ -n "$coverage_seeds" ]] && cov_args+=(--seeds "$coverage_seeds")
    ((coverage_rand > 0)) && cov_args+=(--rand-num "$coverage_rand")
    ((allow_miss)) && cov_args+=(--allow-miss)
    if ((apply_waiver)); then
        cov_args+=(--waiver --waiver-file "$waiver_file" --waiver-manifest "$waiver_manifest")
    fi
    runner_run_coverage "${cov_args[@]}" || {
        printf 'status=coverage-fail\n' >> "$run_meta"
        printf '[PHASE 1/2] COVERAGE fail\n'
        runner_report_signoff "$run_id" "$root" FAIL FAIL NOT_RUN "$coverage_summary" "$regression_summary"
        return 1
    }
    [[ "$log_style" != compact ]] || printf '[PHASE 1/2] COVERAGE complete\n'
    ((phase_wait > 0)) && sleep "$phase_wait"

    [[ "$log_style" != compact ]] || printf '[PHASE 2/2] REGRESSION start\n'
    local -a reg_args=("${selection[@]}" --id "${run_id}_regression" "${common[@]}" "${regression_extra[@]}")
    [[ -n "$regression_seeds" ]] && reg_args+=(--seeds "$regression_seeds")
    ((regression_rand > 0)) && reg_args+=(--rand-num "$regression_rand")
    runner_run_regression "${reg_args[@]}" || {
        printf 'status=regression-fail\n' >> "$run_meta"
        printf '[PHASE 2/2] REGRESSION fail\n'
        runner_report_signoff "$run_id" "$root" FAIL PASS FAIL "$coverage_summary" "$regression_summary"
        return 1
    }
    [[ "$log_style" != compact ]] || printf '[PHASE 2/2] REGRESSION pass\n'
    printf 'status=pass\ncompleted=%s\n' "$(date -Is)" >> "$run_meta"
    runner_report_signoff "$run_id" "$root" PASS PASS PASS "$coverage_summary" "$regression_summary"
    printf '[PASS] SIGNOFF run=%s\n' "$run_id"
}
