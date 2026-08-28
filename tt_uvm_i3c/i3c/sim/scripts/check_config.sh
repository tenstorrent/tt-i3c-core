#!/usr/bin/env bash

runner_check_config() {
    local failures=0
    [[ -r "$RUNNER_SCRIPT_DIR/vcs_backend.mk" ]] || { runner_error "Missing VCS backend"; failures=1; }
    [[ -x "$RUNNER_SCRIPT_DIR/runner_make.sh" ]] || { runner_error "Missing executable runner_make.sh"; failures=1; }
    [[ -r "${DV_RUNNER_ENTRYPOINT:-$RUNNER_ROOT/run.sh}" ]] || {
        runner_error "Missing run.sh: ${DV_RUNNER_ENTRYPOINT:-$RUNNER_ROOT/run.sh}"
        failures=1
    }

    local script content
    while IFS= read -r -d '' script; do
        content="$(cat "$script")"
        if ! printf '%s' "$content" | bash -n; then
            runner_error "Bash syntax failed: $script"
            failures=1
        fi
    done < <(
        find "$RUNNER_ROOT" -maxdepth 5 \
            \( -path "$RUNNER_ROOT/sim/generated" -o -path "$RUNNER_ROOT/sim/out" \) -prune -o \
            -type f \( -name '*.sh' -o -name '*.bash' \) -print0
    )

    "$RUNNER_SCRIPT_DIR/runner_make.sh" -s print-config || failures=1
    runner_project_print

    local filelist
    filelist="$FILELIST"
    if [[ -n "$filelist" && "$filelist" != /* ]]; then
        filelist="$RUNNER_ROOT/$filelist"
    fi
    if [[ -n "$filelist" && ! -r "$filelist" ]]; then
        if [[ -n "${RUNNER_PROJECT_CONFIG:-}" ]]; then
            runner_error "Configured final VCS filelist is not present: $filelist"; failures=1
        else
            runner_warn "Configured final VCS filelist is not present yet: $filelist"
        fi
    fi
    [[ -n "${RUNNER_PROJECT_CONFIG:-}" ]] || runner_warn "dv_project.sh is not installed; only help/self-test defaults are active"

    local testplan="$TEST_LIST_FILE"
    if [[ -r "$testplan" ]]; then
        grep -Eq '^#[[:space:]]*DV_TESTPLAN_VERSION=(1|2)[[:space:]]*$' "$testplan" || {
            runner_error "Missing supported DV_TESTPLAN_VERSION header: $testplan"; failures=1; }
        awk -F'|' '
            /^#[[:space:]]*DV_TESTPLAN_VERSION=2/ {v2=1; next}
            /^[[:space:]]*#/ || /^[[:space:]]*$/ {next}
            {enabled=v2?$5:$4; policy=v2?$6:$5; tags=v2?$9:$8; requirements=v2?$10:$9}
            (!v2 && (NF < 8 || NF > 9)) || (v2 && (NF < 9 || NF > 10)) {printf "invalid field count at line %d: got %d\n", NR, NF; bad=1}
            v2 && $2 !~ /^[A-Za-z0-9_.-]+$/ {printf "invalid case_id at line %d: %s\n", NR, $2; bad=1}
            enabled !~ /^(on|off)$/ {printf "invalid enabled value at line %d: %s\n", NR, enabled; bad=1}
            policy !~ /^(all|first|random-one|fixed:[1-9][0-9]*|cap:[1-9][0-9]*)$/ {printf "invalid seed policy at line %d: %s\n", NR, policy; bad=1}
            tags ~ /(^|,)coverage-seed=/ && tags !~ /(^|,)coverage-seed=(all|first|random-one|fixed:[1-9][0-9]*|cap:[1-9][0-9]*)(,|$)/ {printf "invalid coverage seed policy at line %d: %s\n", NR, tags; bad=1}
            tags ~ /(^|,)coverage-iteration=/ && tags !~ /(^|,)coverage-iteration=(all|once)(,|$)/ {printf "invalid coverage iteration policy at line %d: %s\n", NR, tags; bad=1}
            requirements !~ /^(|hdl_access)$/ {printf "invalid compile requirements at line %d: %s\n", NR, requirements; bad=1}
            END {exit bad}
        ' "$testplan" || { runner_error "Test-plan schema validation failed: $testplan"; failures=1; }
    else
        if [[ -n "${RUNNER_PROJECT_CONFIG:-}" ]]; then
            runner_error "Configured test plan is not present: $testplan"; failures=1
        else
            runner_warn "Configured test plan is not present yet: $testplan"
        fi
    fi

    local forbidden='u''art|i''3c|i''2c|h''ci|s''mc|a''ou' core_file violations
    local -a core_paths=()
    while IFS= read -r core_file; do
        [[ -z "$core_file" || "$core_file" == \#* ]] || core_paths+=("$RUNNER_ROOT/$core_file")
    done < "$RUNNER_SCRIPT_DIR/generic_core_files.list"
    violations="$(grep -HEni "\\b($forbidden)\\b" "${core_paths[@]}" 2>/dev/null || true)"
    if [[ -n "$violations" ]]; then
        runner_error "IP-specific identifier detected in generic runner sources"
        while IFS= read -r violation; do
            [[ -z "$violation" ]] || runner_error "  $violation"
        done <<< "$violations"
        runner_note "Generic runner files are shared across projects and must remain protocol/IP independent."
        runner_note "Move project-specific paths, names, help, validation, and command behavior to sim/dv_project.sh."
        runner_note "For larger logic, keep it in a project-owned script and invoke it through a dv_project_* hook."
        runner_note "The generic file boundary is defined by sim/scripts/generic_core_files.list."
        failures=1
    fi

    if grep -En '^[[:space:]]*Usage:' "${core_paths[@]:1}" >/dev/null 2>&1; then
        runner_error "Child script contains user help; canonical help must remain in run.sh"
        failures=1
    fi

    if grep -En '\bsrun[[:space:]]+(-|")' "$RUNNER_SCRIPT_DIR/vcs_backend.mk" >/dev/null 2>&1 || \
       grep -ERn --exclude='common_scheduler.sh' --exclude='check_config.sh' --exclude='*.md' '\bsrun[[:space:]]+(-|")' "$RUNNER_SCRIPT_DIR" >/dev/null 2>&1; then
        runner_error "Scheduler submission found outside common_scheduler.sh"
        failures=1
    fi

    if [[ -n "${RUNNER_PROJECT_CONFIG:-}" ]]; then
        runner_project_preflight || failures=1
    fi

    if ((failures == 0)); then
        runner_info "Static configuration checks passed"
    fi
    return "$failures"
}
