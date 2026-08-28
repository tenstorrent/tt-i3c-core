#!/usr/bin/env bash

runner_run_generate() {
    runner_project_generate "$@" || return $?
    [[ -r "$FILELIST" ]] || { runner_error "Generated compile filelist is missing: $FILELIST"; return 2; }
    [[ -r "$TEST_LIST_FILE" ]] || runner_warn "Generated test plan is missing: $TEST_LIST_FILE"
    runner_info "Generation completed"
}
