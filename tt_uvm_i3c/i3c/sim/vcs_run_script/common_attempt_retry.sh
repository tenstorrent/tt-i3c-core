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
# File        : common_attempt_retry.sh
# Description : TT UVM I3C simulation support file.
# Authors     : Duy Huynh, Dang Thai
# Date        : 2026-08-11
#
# *****************************************************************************


RUNNER_SCOREBOARD_FAILURE_REGEX="${RUNNER_SCOREBOARD_FAILURE_REGEX:-scoreboard[[:space:]_-]+(fail(ed|ure)?|mismatch)|scoreboard.*mismatch(es)?[[:space:]]*[:=][[:space:]]*[1-9][0-9]*|[[:alnum:]_]*SB_(FAIL|ERROR|MISMATCH)[[:alnum:]_]*}"
RUNNER_SVA_MARKER_REGEX="${RUNNER_SVA_MARKER_REGEX:-SVA:[[:space:]]*[[:alnum:]_.$:/-]+}"
RUNNER_SVA_FAILURE_REGEX="${RUNNER_SVA_FAILURE_REGEX:-${RUNNER_SVA_MARKER_REGEX}|Assertion.*(fail|error)|assertion[[:space:]_-]*failed|[[:alnum:]_.$/]*ap_[[:alnum:]_]+:.*started at .*failed at}"

runner_log_has_assertion_failure() {
    local file="$1"
    file="$(runner_log_for_analysis "$file")"
    grep -Eiq "$RUNNER_SVA_FAILURE_REGEX" "$file" 2>/dev/null
}

runner_log_has_scoreboard_failure() {
    local file="$1"
    file="$(runner_log_for_analysis "$file")"
    grep -Eiq "$RUNNER_SCOREBOARD_FAILURE_REGEX" "$file" 2>/dev/null
}

runner_retryable_failure() {
    local rc="$1" log_file="$2"
    log_file="$(runner_log_for_analysis "$log_file")"
    (( rc != 0 )) || return 1
    (( rc != 2 )) || return 1
    local functional_regex="${RUNNER_UVM_FAILURE_REGEX}|${RUNNER_PLAIN_ERROR_REGEX}|${RUNNER_SVA_FAILURE_REGEX}|${RUNNER_SCOREBOARD_FAILURE_REGEX}|TEST[[:space:]_-]*FAIL"
    local crash_regex='Segmentation fault|Signal [0-9]+|Internal error|Fatal License Error|SCL-[0-9]+|vcs.*crash|simv.*crash|Killed|Bus error|core dumped|No space left on device|Connection timed out|scheduler.*failed'
    if grep -Eiq "$functional_regex" "$log_file" 2>/dev/null; then
        return 1
    fi
    if [[ -n "${RUNNER_NON_RETRY_REGEX:-}" ]] && grep -Eiq "$RUNNER_NON_RETRY_REGEX" "$log_file"; then
        return 1
    fi
    if [[ -n "${RUNNER_RETRY_REGEX:-}" ]]; then
        grep -Eiq "$RUNNER_RETRY_REGEX" "$log_file"
        return $?
    fi
    grep -Eiq "$crash_regex" "$log_file" 2>/dev/null
}

runner_failure_reason() {
    local rc="$1" log_file="$2"
    log_file="$(runner_log_for_analysis "$log_file")"
    if ((rc == 124 || rc == 125)); then printf 'TIMEOUT\n'; return; fi
    if runner_log_has_assertion_failure "$log_file"; then
        printf 'ASSERT_FAIL\n'; return
    fi
    if runner_log_has_scoreboard_failure "$log_file"; then
        printf 'SCOREBOARD_FAIL\n'; return
    fi
    if grep -Eiq "$RUNNER_UVM_FAILURE_REGEX" "$log_file" 2>/dev/null; then
        printf 'UVM_FAIL\n'; return
    fi
    if grep -Eiq "$RUNNER_PLAIN_ERROR_REGEX" "$log_file" 2>/dev/null; then
        printf 'ERROR_FAIL\n'; return
    fi
    if grep -Eiq 'TEST[[:space:]_-]*FAIL' "$log_file" 2>/dev/null; then
        printf 'TEST_FAIL\n'; return
    fi
    if grep -Eiq 'Fatal License Error|license.*(fail|denied|unavailable)|Cannot connect to the license server|SCL-[0-9]+' "$log_file" 2>/dev/null; then
        printf 'LICENSE_FAIL\n'; return
    fi
    if grep -Eiq 'No space left on device|Disk quota exceeded|File size limit exceeded' "$log_file" 2>/dev/null; then
        printf 'DISK_FAIL\n'; return
    fi
    if grep -Eiq 'srun:.*(error|failed)|scheduler.*failed|slurmstepd: error' "$log_file" 2>/dev/null; then
        printf 'SCHEDULER_FAIL\n'; return
    fi
    if grep -Eiq 'Segmentation fault|Internal error|Bus error|core dumped|vcs.*crash|simv.*crash' "$log_file" 2>/dev/null; then
        printf 'TOOL_FAIL\n'; return
    fi
    if runner_retryable_failure "$rc" "$log_file"; then printf 'INFRA_FAIL\n'; return; fi
    ((rc == 0)) && printf 'PASS\n' || printf 'UNKNOWN\n'
}

runner_failure_phase() {
    case "$1" in
        COMPILE_FAIL) printf 'COMPILE_FAIL\n' ;;
        *) printf 'RUN_FAIL\n' ;;
    esac
}

runner_reason_retryable() {
    case "$1" in
        TOOL_FAIL|INFRA_FAIL|LICENSE_FAIL|DISK_FAIL|SCHEDULER_FAIL|TIMEOUT|UNKNOWN) return 0 ;;
        *) return 1 ;;
    esac
}

runner_log_has_functional_failure() {
    local file="$1" include_warnings="${2:-0}"
    file="$(runner_log_for_analysis "$file")"
    grep -Eiq "${RUNNER_UVM_FAILURE_REGEX}|${RUNNER_SVA_FAILURE_REGEX}|${RUNNER_SCOREBOARD_FAILURE_REGEX}|TEST[[:space:]_-]*FAIL" "$file" 2>/dev/null && return 0
    grep -Eiq "$RUNNER_PLAIN_ERROR_REGEX" "$file" 2>/dev/null && return 0
    ((include_warnings)) && grep -Eiq 'UVM_WARNING[[:space:]]*:[[:space:]]*[1-9]' "$file" 2>/dev/null
}

runner_log_has_completion() {
    local file="$1"
    file="$(runner_log_for_analysis "$file")"
    grep -Eiq "${DV_PASS_REGEX:-UVM Report Summary|UVM_REPORT_SUMMARY|UVM/REPORT/(SERVER|CATCHER)}" "$file" 2>/dev/null
}

runner_attempt_history_line() {
    local label="$1" attempt="$2" rc="$3" log_file="$4"
    printf '[ATTEMPT] label=%s attempt=%s rc=%s log=%s\n' "$label" "$attempt" "$rc" "$log_file"
}
