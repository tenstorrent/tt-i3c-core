#!/usr/bin/env bash

RUNNER_SCRIPT_DIR="${RUNNER_SCRIPT_DIR:-$RUNNER_ROOT/sim/scripts}"

# shellcheck source=scripts/common.sh
source "$RUNNER_SCRIPT_DIR/common.sh"
source "$RUNNER_SCRIPT_DIR/common_scheduler.sh"
source "$RUNNER_SCRIPT_DIR/common_active_jobs.sh"
source "$RUNNER_SCRIPT_DIR/common_live_output.sh"
source "$RUNNER_SCRIPT_DIR/common_reporting.sh"
source "$RUNNER_SCRIPT_DIR/common_attempt_retry.sh"
source "$RUNNER_SCRIPT_DIR/completion_link.sh"
source "$RUNNER_SCRIPT_DIR/run_generate.sh"
source "$RUNNER_SCRIPT_DIR/run_compile.sh"
source "$RUNNER_SCRIPT_DIR/run_test.sh"
source "$RUNNER_SCRIPT_DIR/run_regression.sh"
source "$RUNNER_SCRIPT_DIR/merge_cov.sh"
source "$RUNNER_SCRIPT_DIR/run_coverage.sh"
source "$RUNNER_SCRIPT_DIR/open_wave.sh"
source "$RUNNER_SCRIPT_DIR/clean.sh"
source "$RUNNER_SCRIPT_DIR/summary.sh"
source "$RUNNER_SCRIPT_DIR/signoff.sh"
source "$RUNNER_SCRIPT_DIR/check_config.sh"
source "$RUNNER_SCRIPT_DIR/self_test.sh"

runner_list_tests() {
    local test_file page=1 page_size="${RUNNER_TEST_PAGE_SIZE:-20}" view=head format=human
    local show_all=0 page_set=0 view_set=0 total total_pages first last index index_width
    local version test case_id group level enabled seed_policy seeds plusargs tags requirements
    local state state_gap case_display plusargs_display
    local -a rows=()

    while (($#)); do
        case "$1" in
            -a|--all) show_all=1; shift ;;
            --head) [[ $view_set -eq 0 ]] || { runner_die "Only one of --head or --tail may be used"; return $?; }; view=head; view_set=1; shift ;;
            --tail) [[ $view_set -eq 0 ]] || { runner_die "Only one of --head or --tail may be used"; return $?; }; view=tail; view_set=1; shift ;;
            --page) (($# >= 2)) || { runner_die "--page requires a value"; return $?; }; page="$2"; page_set=1; shift 2 ;;
            --page-size) (($# >= 2)) || { runner_die "--page-size requires a value"; return $?; }; page_size="$2"; shift 2 ;;
            --format) (($# >= 2)) || { runner_die "--format requires a value"; return $?; }; format="$2"; shift 2 ;;
            ''|*[!0-9]*) runner_die "Unknown list-tests option: $1"; return $? ;;
            *) [[ $page_set -eq 0 ]] || { runner_die "Page was specified more than once"; return $?; }; page="$1"; page_set=1; shift ;;
        esac
    done
    [[ "$page_size" =~ ^[1-9][0-9]*$ ]] || { runner_die "--page-size must be a positive integer"; return $?; }
    [[ "$page" =~ ^[1-9][0-9]*$ ]] || { runner_die "--page must be a positive integer"; return $?; }
    [[ "$format" == human || "$format" == raw ]] || { runner_die "--format must be human or raw"; return $?; }
    if ((show_all)) && ((page_set || view_set)); then
        runner_die "--all cannot be combined with --page, --head, or --tail"
        return $?
    fi
    if ((page_set && view_set)); then
        runner_die "--page cannot be combined with --head or --tail"
        return $?
    fi
    ((page_set)) && view=page
    if [[ "$format" == raw && $show_all -eq 0 ]]; then
        runner_die "--format raw requires --all"
        return $?
    fi

    runner_project_generate >/dev/null || return $?
    test_file="${TEST_LIST_FILE:-$(runner_make_value print-test-list)}"
    [[ "$test_file" == /* ]] || test_file="$RUNNER_ROOT/$test_file"
    [[ -r "$test_file" ]] || { runner_die "Test-list file is not readable: $test_file"; return $?; }
    mapfile -t rows < <(awk '!/^[[:space:]]*#/ && !/^[[:space:]]*$/' "$test_file")
    total="${#rows[@]}"

    if [[ "$format" == raw ]]; then
        printf '%s\n' '# test|case_id|group|level|enabled|seed_policy|default_seeds|plusargs|tags|compile_requirements'
        printf '%s\n' "${rows[@]}"
        return 0
    fi

    if ((show_all)); then
        first=1; last="$total"
        printf 'Test List | All entries 1-%s/%s\n' "$last" "$total"
    elif ((total == 0)); then
        first=1; last=0; page=0; total_pages=0
        printf 'Test List | Page 0/0 | Entries 0/0 | Page size %s\n' "$page_size"
    else
        total_pages=$(( (total + page_size - 1) / page_size ))
        [[ "$view" == tail && $page_set -eq 0 ]] && page="$total_pages"
        ((page <= total_pages)) || { runner_die "Page $page exceeds total pages $total_pages"; return $?; }
        first=$(( (page - 1) * page_size + 1 ))
        last=$(( page * page_size )); ((last > total)) && last="$total"
        printf 'Test List | Page %s/%s | Entries %s-%s/%s | Page size %s | View %s\n' \
            "$page" "$total_pages" "$first" "$last" "$total" "$page_size" "$view"
    fi
    index_width="${#total}"
    printf "Legend: T=test, C=case; C=- is the default case; --plusargs is a copyable test-command option.\n"

    for ((index=first-1; index<last; index++)); do
        IFS='|' read -r test case_id group level enabled seed_policy seeds plusargs tags requirements <<< "${rows[$index]}"
        state=$([[ "$enabled" == on ]] && printf ON || printf OFF)
        state_gap=$([[ "$enabled" == on ]] && printf '  ' || printf ' ')
        case_display="$case_id"; [[ "$case_display" == "$test" ]] && case_display='-'
        plusargs_display="${plusargs//\\/\\\\}"
        plusargs_display="${plusargs_display//\"/\\\"}"
        plusargs_display="${plusargs_display//\$/\\\$}"
        plusargs_display="${plusargs_display//\`/\\\`}"
        printf "[%0*d/%s][%s]%sT=%-60s | C=%-40s | --plusargs \"%s\"\n" \
            "$index_width" "$((index + 1))" "$total" "$state" "$state_gap" "$test" "$case_display" "$plusargs_display"
    done

    ((show_all || total == 0)) && return 0
    printf 'Navigation:\n'
    ((page > 1)) && printf '  Previous : ./run.sh list-tests --page %s --page-size %s\n' "$((page - 1))" "$page_size"
    ((page < total_pages)) && printf '  Next     : ./run.sh list-tests --page %s --page-size %s\n' "$((page + 1))" "$page_size"
    ((page != 1)) && printf '  Head     : ./run.sh list-tests --head --page-size %s\n' "$page_size"
    ((page != total_pages)) && printf '  Tail     : ./run.sh list-tests --tail --page-size %s\n' "$page_size"
    printf '  Show all : ./run.sh list-tests --all\n'
    printf '  Resize   : ./run.sh list-tests --page-size 40\n'
}

runner_dispatch_detached() {
    local -a args=("$@") filtered=()
    local arg
    for arg in "${args[@]}"; do
        [[ "$arg" == '--detach' ]] || filtered+=("$arg")
    done
    runner_prepare_out_dir
    local log_dir="$(runner_out_dir)/logs/detached"
    local log_file="$log_dir/${filtered[0]:-command}_$(runner_timestamp).log"
    mkdir -p "$log_dir"
    nohup "${DV_RUNNER_ENTRYPOINT:-$RUNNER_ROOT/run.sh}" "${filtered[@]}" >"$log_file" 2>&1 < /dev/null &
    local pid=$!
    runner_register_job "$pid" "detached.${filtered[0]:-command}" "$log_file"
    runner_info "Detached pid=$pid log=$log_file"
}

runner_dispatch_command() {
    local command="${1:-help}"
    (($# == 0)) || shift

    if [[ "${1:-}" == '-h' || "${1:-}" == '--help' ]]; then
        case "$command" in
            view|wave) ;;
            *) runner_print_help "$command"; return $? ;;
        esac
    fi

    local arg
    for arg in "$@"; do
        if [[ "$arg" == '--detach' ]]; then
            runner_dispatch_detached "$command" "$@"
            return $?
        fi
    done

    case "$command" in
        help|-h|--help) runner_print_help "$@" ;;
        --link|link-completion) runner_completion_link_bash "$@" ;;
        completion) runner_completion_command "$@" ;;
        generate|gen) runner_run_generate "$@" ;;
        comp|compile) runner_run_compile "$@" ;;
        test) runner_run_test "$@" ;;
        regression|regress) runner_run_regression "$@" ;;
        coverage|cov) runner_run_coverage "$@" ;;
        merge-cov) runner_merge_coverage "$@" ;;
        wave|view) runner_open_wave "$@" ;;
        summary) runner_show_summary "$@" ;;
        signoff) runner_run_signoff "$@" ;;
        list-tests) runner_list_tests "$@" ;;
        jobs) runner_list_jobs ;;
        stop-jobs) runner_stop_jobs ;;
        doctor|check) runner_check_config ;;
        self-test) runner_self_test ;;
        clean) runner_clean "$@" ;;
        *)
            runner_error "Unknown command: $command"
            runner_print_help >&2
            return 2
            ;;
    esac
}

runner_dispatch() {
    local command="${1:-help}" start rc=0
    local -a original=("$@")
    case "$command" in
        help|-h|--help|completion|--link|link-completion|list-tests)
            runner_dispatch_command "${original[@]}"
            return $?
            ;;
    esac
    if [[ "${original[1]:-}" == '-h' || "${original[1]:-}" == '--help' ]]; then
        runner_dispatch_command "${original[@]}"
        return $?
    fi
    start="$(date +%s)"
    runner_report_command_start "$command" "${original[@]:1}"
    runner_dispatch_command "${original[@]}" || rc=$?
    runner_report_command_end "$command" "$rc" "$start"
    return "$rc"
}
