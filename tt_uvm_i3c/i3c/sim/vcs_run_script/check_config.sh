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
# File        : check_config.sh
# Description : TT UVM I3C simulation support file.
# Authors     : Duy Huynh, Dang Thai
# Date        : 2026-08-11
#
# *****************************************************************************


runner_check_config() {
    local failures=0
    [[ -r "$RUNNER_SCRIPT_DIR/vcs_backend.mk" ]] || { runner_error "Missing VCS backend"; failures=1; }
    [[ -x "$RUNNER_SCRIPT_DIR/runner_make.sh" ]] || { runner_error "Missing executable runner_make.sh"; failures=1; }
    [[ -x "${DV_RUNNER_ENTRYPOINT:-}" ]] ||
        { runner_error "Missing executable runner entry point: ${DV_RUNNER_ENTRYPOINT:-<unset>}"; failures=1; }

    local script content
    while IFS= read -r -d '' script; do
        content="$(cat "$script")"
        if ! printf '%s' "$content" | bash -n; then
            runner_error "Bash syntax failed: $script"
            failures=1
        fi
    done < <(
        find "${PACKAGE_ROOT:-$RUNNER_ROOT}" -maxdepth 5 \
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
    [[ -n "${RUNNER_PROJECT_CONFIG:-}" ]] || runner_warn "dv_project.sh is not installed; only generic help is active"

    local testplan="$TEST_LIST_FILE"
    if [[ -r "$testplan" ]]; then
        grep -Eq '^#[[:space:]]*DV_TESTPLAN_VERSION=1[[:space:]]*$' "$testplan" || {
            runner_error "Missing DV_TESTPLAN_VERSION=1 header: $testplan"; failures=1; }
        awk -F'|' '
            /^[[:space:]]*#/ || /^[[:space:]]*$/ {next}
            NF != 8 {printf "invalid field count at line %d: expected 8, got %d\n", NR, NF; bad=1}
            $4 !~ /^(on|off)$/ {printf "invalid enabled value at line %d: %s\n", NR, $4; bad=1}
            $5 !~ /^(all|first|random-one)$/ {printf "invalid seed policy at line %d: %s\n", NR, $5; bad=1}
            END {exit bad}
        ' "$testplan" || { runner_error "Test-plan schema validation failed: $testplan"; failures=1; }
    else
        if [[ -n "${RUNNER_PROJECT_CONFIG:-}" ]]; then
            runner_error "Configured test plan is not present: $testplan"; failures=1
        else
            runner_warn "Configured test plan is not present yet: $testplan"
        fi
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
