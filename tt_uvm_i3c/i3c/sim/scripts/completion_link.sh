#!/usr/bin/env bash

runner_completion_link_usage() {
    cat <<'EOF'
Usage:
  source ./run.sh --link [--rc-file <path>]
  ./run.sh --link [--rc-file <path>]
  ./run.sh link-completion [--rc-file <path>]
  ./run.sh completion --link [--rc-file <path>]

Install Bash completion persistently in ~/.bashrc or the selected rc file.
Source run.sh to install and activate completion in the current shell.
EOF
}

runner_completion_default_rc_file() {
    if [[ -n "${DV_RUNNER_COMPLETION_RC:-}" ]]; then
        printf '%s\n' "$DV_RUNNER_COMPLETION_RC"
    elif [[ -n "${HOME:-}" ]]; then
        printf '%s/.bashrc\n' "$HOME"
    else
        return 1
    fi
}

runner_completion_expand_home_path() {
    local path="$1"
    case "$path" in
        '~') [[ -n "${HOME:-}" ]] || return 1; printf '%s\n' "$HOME" ;;
        '~/'*) [[ -n "${HOME:-}" ]] || return 1; printf '%s/%s\n' "$HOME" "${path#~/}" ;;
        *) printf '%s\n' "$path" ;;
    esac
}

runner_completion_link_bash() {
    local rc_file='' rc_dir tmp_file marker
    local begin_marker end_marker completion_q

    while (($#)); do
        case "$1" in
            --rc-file)
                [[ $# -ge 2 && -n "${2:-}" ]] || { runner_error "--rc-file requires a path"; return 2; }
                rc_file="$2"; shift 2
                ;;
            -h|--help) runner_completion_link_usage; return 0 ;;
            *) runner_error "Unsupported --link option: $1"; runner_completion_link_usage >&2; return 2 ;;
        esac
    done

    [[ -r "$RUNNER_SCRIPT_DIR/run_completion.bash" ]] || {
        runner_error "Completion script not found: $RUNNER_SCRIPT_DIR/run_completion.bash"; return 1; }

    if [[ -z "$rc_file" ]]; then
        rc_file="$(runner_completion_default_rc_file)" || {
            runner_error "HOME is not set; pass --rc-file <path>"; return 1; }
    fi
    rc_file="$(runner_completion_expand_home_path "$rc_file")" || {
        runner_error "Cannot expand rc-file path without HOME: $rc_file"; return 1; }

    marker="$RUNNER_ROOT"
    marker="${marker//[^[:alnum:]_.-]/_}"
    begin_marker="# >>> Generic DV Runner completion: $marker >>>"
    end_marker="# <<< Generic DV Runner completion: $marker <<<"
    rc_dir="$(dirname "$rc_file")"
    mkdir -p "$rc_dir"
    touch "$rc_file"
    tmp_file="$(mktemp "$rc_dir/.dv_runner_completion.XXXXXX")" || return 1

    if ! awk -v begin="$begin_marker" -v end="$end_marker" '
        $0 == begin { skip = 1; next }
        $0 == end { skip = 0; next }
        !skip { print }
        END { if (skip) exit 2 }
    ' "$rc_file" > "$tmp_file"; then
        rm -f "$tmp_file"
        runner_error "Incomplete managed completion block in: $rc_file"
        runner_error "Remove or repair the stale block, then rerun --link"
        return 1
    fi

    completion_q="$(printf '%q' "$RUNNER_SCRIPT_DIR/run_completion.bash")"
    {
        printf '\n%s\n' "$begin_marker"
        printf '# Added by %s --link\n' "${DV_RUNNER_ENTRYPOINT:-$RUNNER_ROOT/run.sh}"
        printf 'if [[ -r %s ]]; then\n' "$completion_q"
        printf '    source %s\n' "$completion_q"
        printf 'fi\n'
        printf '%s\n' "$end_marker"
    } >> "$tmp_file"

    chmod --reference="$rc_file" "$tmp_file" 2>/dev/null || true
    mv "$tmp_file" "$rc_file"
    runner_info "Installed Bash completion into: $rc_file"
    runner_info "Restart Bash or run: source $(printf '%q' "${DV_RUNNER_ENTRYPOINT:-$RUNNER_ROOT/run.sh}") completion bash"
}

runner_completion_command() {
    case "${1:-}" in
        bash)
            printf 'source %q\n' "$RUNNER_SCRIPT_DIR/run_completion.bash"
            ;;
        tests|cases|groups)
            local test_file
            test_file="$(runner_make_value print-test-list)" || return 0
            [[ -n "$test_file" ]] || return 0
            [[ "$test_file" == /* ]] || test_file="$RUNNER_ROOT/$test_file"
            [[ -r "$test_file" && ! -d "$test_file" ]] || return 0
            case "$1" in
                tests) awk -F'|' '!/^[[:space:]]*#/ && NF {print $1}' "$test_file" | sort -u ;;
                cases) awk -F'|' '!/^[[:space:]]*#/ && NF {print $2}' "$test_file" | sort -u ;;
                groups) awk -F'|' '!/^[[:space:]]*#/ && NF {print $3}' "$test_file" | sort -u ;;
            esac
            ;;
        --link|link)
            shift
            runner_completion_link_bash "$@"
            ;;
        ''|-h|--help)
            runner_completion_link_usage
            ;;
        *)
            runner_error "Unsupported completion mode: $1"
            runner_completion_link_usage >&2
            return 2
            ;;
    esac
}
