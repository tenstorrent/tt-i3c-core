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
# File        : open_wave.sh
# Description : TT UVM I3C simulation support file.
# Authors     : Duy Huynh, Dang Thai
# Date        : 2026-08-11
#
# *****************************************************************************


runner_wave_print_guide() {
    local example_test="${DV_HELP_EXAMPLE_TEST:-smoke_test}"
    cat <<EOF
Wave And Log Viewer

List/open VCD, VPD, or FSDB dumps and inspect their matching test/compile logs.

Options:
  select : --dump, --log, --compile, --file, --last
  filter : --test, --seed, --format, --fsdb, --vcd, --vpd, --limit
  action : --open, --tail, --show-log, --show-compile, --open-log, --open-compile
  viewer : --viewer, --source-map auto|off|reparse, --scheduler, --cpus, --x11

Examples:
  ./run.sh view --any-dump --limit 10
  ./run.sh view --open --last --fsdb
  ./run.sh view --open --last --fsdb --source-map reparse
  ./run.sh view --open --last --test $example_test --seed 1 --fsdb
  ./run.sh view --log --last --test $example_test --seed 1 --tail 120
  ./run.sh view --compile --last --show-compile

Read the package README and docs for waveform and source-mapping contracts.
EOF
}

runner_wave_candidates() {
    local format="$1" out
    out="$(runner_out_dir)"; [[ -d "$out" ]] || return 0
    case "$format" in
        fsdb|vcd|vpd) find "$out" -type f -name "*.$format" ! -path '*/.wave_cache/*' -printf '%T@|%p\n' 2>/dev/null ;;
        any|'') find "$out" -type f \( -name '*.fsdb' -o -name '*.vcd' -o -name '*.vpd' \) ! -path '*/.wave_cache/*' -printf '%T@|%p\n' 2>/dev/null ;;
        *) runner_die "Unsupported waveform format: $format"; return $? ;;
    esac
}

runner_wave_find() {
    local format="$1" identifier="$2" test_name="$3" seed="$4" line path base
    while IFS='|' read -r _ path; do
        base="$(basename "$path")"
        [[ -z "$identifier" || "$identifier" == 'last' || "$path" == *"$identifier"* || "$base" == "$identifier" || "${base%.*}" == "$identifier" ]] || continue
        [[ -z "$test_name" || "$path" == *"$test_name"* ]] || continue
        [[ -z "$seed" || "$path" == *"seed_${seed}"* || "$path" == *"seed${seed}"* ]] || continue
        printf '%s\n' "$path"; return 0
    done < <(runner_wave_candidates "$format" | sort -t'|' -k1,1nr)
    return 1
}

runner_wave_find_log() {
    local kind="$1" identifier="$2" test_name="$3" seed="$4" out pattern
    out="$(runner_out_dir)"; [[ -d "$out" ]] || return 1
    if [[ "$kind" == compile ]]; then pattern='compile.log'; else pattern='*.log'; fi
    local path
    while IFS= read -r path; do
        [[ -z "$identifier" || "$identifier" == 'last' || "$path" == *"$identifier"* ]] || continue
        [[ -z "$test_name" || "$path" == *"$test_name"* ]] || continue
        [[ -z "$seed" || "$path" == *"seed_${seed}"* ]] || continue
        printf '%s\n' "$path"; return 0
    done < <(find "$out" -type f -name "$pattern" -printf '%T@|%p\n' 2>/dev/null | sort -t'|' -k1,1nr | cut -d'|' -f2-)
    return 1
}

runner_wave_mapped_log() {
    local wave="$1" attempt_dir candidate
    attempt_dir="$(dirname "$(dirname "$wave")")"
    for candidate in "$attempt_dir/logs/sim.clean.log" \
                     "$attempt_dir/logs/sim.log"; do
        [[ -f "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
    done
    return 1
}

runner_wave_display_path() {
    local path="$1"
    if declare -F runner_report_path >/dev/null 2>&1; then
        runner_report_path "$path"
    elif [[ "$path" == "$RUNNER_ROOT/"* ]]; then
        printf '%s\n' "${path#"$RUNNER_ROOT/"}"
    else
        printf '%s\n' "$path"
    fi
}

runner_wave_list() {
    local format="$1" limit="$2" count=0 path mapped display_wave display_log
    local run_id test_name seed attempt extension stem
    while IFS='|' read -r _ path; do
        count=$((count + 1))
        run_id='unknown'; test_name='unknown'; seed='?'; attempt='-'
        extension="${path##*.}"; extension="${extension^^}"
        if [[ "$path" =~ /runs/([^/]+)/cases/([^/]+)/seed_([^/]+)/attempt_([0-9]+)/dumps/ ]]; then
            run_id="${BASH_REMATCH[1]}"
            test_name="${BASH_REMATCH[2]}"
            seed="${BASH_REMATCH[3]}"
            printf -v attempt 'A%03d' "$((10#${BASH_REMATCH[4]}))"
        else
            stem="$(basename "$path")"; stem="${stem%.*}"
            if [[ "$stem" =~ ^(.+)_seed_?([0-9]+) ]]; then
                test_name="${BASH_REMATCH[1]}"; seed="${BASH_REMATCH[2]}"
            fi
        fi
        mapped="$(runner_wave_mapped_log "$path" 2>/dev/null || true)"
        display_wave="$(runner_wave_display_path "$path")"
        display_log='(not found)'
        [[ -z "$mapped" ]] || display_log="$(runner_wave_display_path "$mapped")"
        printf '[%d] %-5s %s  seed=%s  %s\n' \
            "$count" "$extension" "$test_name" "$seed" "$attempt"
        printf '    run : %s\n' "$run_id"
        printf '    wave: %s\n' "$display_wave"
        printf '    log : %s\n' "$display_log"
        printf '%s\n' '-------------------------------------------------------------------------'
        ((count >= limit)) && break
    done < <(runner_wave_candidates "$format" | sort -t'|' -k1,1nr)
    ((count > 0)) || runner_info "No waveform dumps found under $(runner_out_dir)"
}

runner_try_vcd_to_fsdb() {
    local vcd="$1" fsdb="$2" work_dir="$3" tool tool_path rc
    local log_file
    local -a tools=("${VCD2FSDB:-vcd2fsdb}" "${VFAST:-vfast}")

    mkdir -p "$(dirname "$fsdb")" "$work_dir" || return 1
    vcd="$(cd "$(dirname "$vcd")" && pwd)/$(basename "$vcd")" || return 1
    fsdb="$(cd "$(dirname "$fsdb")" && pwd)/$(basename "$fsdb")" || return 1
    work_dir="$(cd "$work_dir" && pwd)" || return 1
    log_file="$work_dir/conversion.log"
    : > "$log_file"

    for tool in "${tools[@]}"; do
        tool_path="$(command -v "$tool" 2>/dev/null || true)"
        if [[ -z "$tool_path" && -x "$tool" ]]; then
            tool_path="$(cd "$(dirname "$tool")" && pwd)/$(basename "$tool")"
        fi
        [[ -n "$tool_path" ]] || continue

        local variant
        local -a args=()
        for variant in positional_output input_output positional_pair output_input; do
            case "$variant" in
                positional_output) args=("$vcd" -o "$fsdb") ;;
                input_output)      args=(-i "$vcd" -o "$fsdb") ;;
                positional_pair)   args=("$vcd" "$fsdb") ;;
                output_input)      args=(-o "$fsdb" "$vcd") ;;
            esac
            rm -f "$fsdb"
            {
                printf '[TRY]'
                printf ' %q' "$tool_path" "${args[@]}"
                printf '\n'
            } >> "$log_file"
            (cd "$work_dir" && "$tool_path" "${args[@]}") >> "$log_file" 2>&1
            rc=$?
            printf '[RESULT] rc=%d fsdb=%s\n' "$rc" \
                "$([[ -f "$fsdb" ]] && printf created || printf missing)" >> "$log_file"
            ((rc == 0)) && [[ -f "$fsdb" ]] && return 0
        done
    done
    return 1
}

runner_wave_meta_value() {
    local meta="$1" key="$2"
    [[ -r "$meta" ]] || return 1
    awk -v key="$key" 'index($0, key "=") == 1 {print substr($0, length(key) + 2); exit}' "$meta"
}

runner_wave_find_compile_meta() {
    local wave="$1" current
    current="$(cd "$(dirname "$wave")" 2>/dev/null && pwd -P)" || return 1
    while [[ -n "$current" && "$current" != / ]]; do
        if [[ -r "$current/compile.meta" ]]; then
            printf '%s\n' "$current/compile.meta"
            return 0
        fi
        [[ "$current" == "$(dirname "$current")" ]] && break
        current="$(dirname "$current")"
    done
    return 1
}

runner_wave_append_verdi_uvm_args() {
    local uvm_root="${DV_UVM_HOME:-${UVM_HOME:-}}" uvm_src=''
    [[ "${DV_UVM_MODE:-${UVM_MODE:-builtin}}" == external ]] || return 0
    if [[ -f "$uvm_root/uvm_pkg.sv" ]]; then
        uvm_src="$uvm_root"
    elif [[ -f "$uvm_root/src/uvm_pkg.sv" ]]; then
        uvm_src="$uvm_root/src"
    fi
    [[ -n "$uvm_src" ]] || return 0
    RUNNER_WAVE_SOURCE_ARGS+=("+incdir+$uvm_src" "$uvm_src/uvm_pkg.sv")
}

runner_wave_prepare_verdi_source_context() {
    local wave="$1" requested="$2" meta='' build_dir='' debug_db=''
    local project_top="${DV_VERDI_TOP:-${DV_TOP:-${TOP:-}}}"
    local project_filelist="${DV_VERDI_FILELIST:-${FILELIST:-}}"
    local project_work_dir="${DV_VERDI_WORK_DIR:-${COMPILE_WORK_DIR:-$RUNNER_ROOT}}"
    local top="$project_top" filelist="$project_filelist" work_dir="$project_work_dir"
    local recorded_sha='' current_sha='' kdb_valid=0 value
    local -a extra_args=()

    RUNNER_WAVE_SOURCE_ARGS=()
    RUNNER_WAVE_SOURCE_ACTUAL=off
    RUNNER_WAVE_SOURCE_META=''
    RUNNER_WAVE_SOURCE_WORK_DIR="$(dirname "$wave")"
    [[ "$requested" != off ]] || return 0

    meta="$(runner_wave_find_compile_meta "$wave" 2>/dev/null || true)"
    if [[ -n "$meta" && -r "$meta" ]]; then
        RUNNER_WAVE_SOURCE_META="$meta"
        value="$(runner_wave_meta_value "$meta" top || true)"; [[ -z "$value" ]] || top="$value"
        value="$(runner_wave_meta_value "$meta" filelist || true)"; [[ -z "$value" ]] || filelist="$value"
        value="$(runner_wave_meta_value "$meta" compile_work_dir || true)"; [[ -z "$value" ]] || work_dir="$value"
        build_dir="$(runner_wave_meta_value "$meta" build_dir || true)"
        debug_db="$(runner_wave_meta_value "$meta" debug_db || true)"
        kdb_valid="$(runner_wave_meta_value "$meta" verdi_kdb || true)"
        recorded_sha="$(runner_wave_meta_value "$meta" git_sha || true)"
    fi
    [[ -n "$debug_db" || -z "$build_dir" ]] || debug_db="$build_dir/simv.daidir"
    [[ -z "$debug_db" || "$debug_db" == /* ]] || debug_db="$RUNNER_ROOT/$debug_db"
    [[ -z "$filelist" || "$filelist" == /* ]] || filelist="$RUNNER_ROOT/$filelist"
    [[ -z "$work_dir" || "$work_dir" == /* ]] || work_dir="$RUNNER_ROOT/$work_dir"
    [[ -z "$project_filelist" || "$project_filelist" == /* ]] || project_filelist="$RUNNER_ROOT/$project_filelist"
    [[ -z "$project_work_dir" || "$project_work_dir" == /* ]] || project_work_dir="$RUNNER_ROOT/$project_work_dir"
    if [[ ! -r "$filelist" && -r "$project_filelist" ]]; then
        runner_info "Recorded Verdi filelist is unavailable; using current project filelist: $project_filelist"
        filelist="$project_filelist"
    fi
    if [[ ! -d "$work_dir" && -d "$project_work_dir" ]]; then
        runner_info "Recorded compile work directory is unavailable; using current project directory: $project_work_dir"
        work_dir="$project_work_dir"
    fi
    [[ -n "$top" ]] || top="$project_top"

    if [[ "$requested" == auto && "$kdb_valid" == 1 && -d "$debug_db" ]]; then
        RUNNER_WAVE_SOURCE_ARGS=(-dbdir "$debug_db")
        RUNNER_WAVE_SOURCE_ACTUAL=debug-db
        [[ -d "$work_dir" ]] && RUNNER_WAVE_SOURCE_WORK_DIR="$work_dir"
    elif [[ -r "$filelist" && -n "$top" && -d "$work_dir" ]]; then
        runner_wave_append_verdi_uvm_args
        RUNNER_WAVE_SOURCE_ARGS+=(-sv -f "$filelist" -top "$top")
        if [[ -n "${DV_VERDI_SOURCE_OPTS:-}" ]]; then
            read -r -a extra_args <<< "$DV_VERDI_SOURCE_OPTS"
            RUNNER_WAVE_SOURCE_ARGS+=("${extra_args[@]}")
        fi
        RUNNER_WAVE_SOURCE_ACTUAL=reparse
        RUNNER_WAVE_SOURCE_WORK_DIR="$work_dir"
    elif [[ "$requested" == reparse ]]; then
        runner_error "Verdi reparse requires readable filelist, top, and compile work directory"
        runner_error "filelist=${filelist:-unset} top=${top:-unset} work_dir=${work_dir:-unset}"
        return 2
    else
        runner_info "Verdi source context is unavailable; opening waveform without source mapping"
    fi

    if [[ -n "$recorded_sha" ]] && command -v git >/dev/null 2>&1; then
        current_sha="$(git -C "$RUNNER_ROOT" rev-parse HEAD 2>/dev/null || true)"
        if [[ -n "$current_sha" && "$current_sha" != "$recorded_sha" ]]; then
            runner_info "Source revision differs from waveform compile: recorded=$recorded_sha current=$current_sha"
        fi
    fi
}

runner_wave_open_dump() {
    local wave_file="$1" viewer="$2" scheduler="$3" cpus="$4" x11="$5" source_mode="$6"
    local ext="${wave_file##*.}" open_file="$wave_file" cache_dir convert_dir launch_dir="$(dirname "$wave_file")"
    if [[ "${ext,,}" == vcd && ( -z "$viewer" || "$viewer" == *verdi* ) ]]; then
        cache_dir="$(dirname "$wave_file")/.wave_cache"; mkdir -p "$cache_dir"
        open_file="$cache_dir/$(basename "$wave_file").fsdb"
        convert_dir="$cache_dir/$(basename "$wave_file").convert"
        if [[ ! -f "$open_file" || "$wave_file" -nt "$open_file" ]]; then
            runner_info "Converting VCD to FSDB cache: $open_file"
            runner_try_vcd_to_fsdb "$wave_file" "$open_file" "$convert_dir" || {
                runner_error "VCD conversion failed; log=$convert_dir/conversion.log"
                runner_error "Set --viewer to a VCD-capable viewer or generate FSDB"
                return 2
            }
        fi
        ext=fsdb
    fi
    if [[ -z "$viewer" ]]; then
        case "${ext,,}" in
            fsdb) viewer="${FSDB_VIEWER:-verdi}" ;;
            vpd) viewer="${VPD_VIEWER:-dve -vpd}" ;;
            vcd) viewer="${VCD_VIEWER:-gtkwave}" ;;
        esac
    fi
    local -a viewer_args launch_args=()
    read -r -a viewer_args <<< "$viewer"
    local viewer_name="$(basename "${viewer_args[0]}")" arg
    if [[ "${ext,,}" == fsdb && "${viewer_name,,}" == *verdi* ]]; then
        runner_wave_prepare_verdi_source_context "$wave_file" "$source_mode" || return $?
        for arg in "${viewer_args[@]}"; do
            [[ "$arg" == -ssf ]] || launch_args+=("$arg")
        done
        launch_args+=("${RUNNER_WAVE_SOURCE_ARGS[@]}" -ssf "$open_file")
        launch_dir="$RUNNER_WAVE_SOURCE_WORK_DIR"
        runner_info "Verdi source map: $RUNNER_WAVE_SOURCE_ACTUAL"
        [[ -z "$RUNNER_WAVE_SOURCE_META" ]] || runner_info "Compile metadata: $RUNNER_WAVE_SOURCE_META"
    else
        launch_args=("${viewer_args[@]}" "$open_file")
        if [[ "$source_mode" != off ]]; then
            runner_info "Source mapping is available only with the Verdi FSDB viewer; opening with source map off"
        fi
    fi
    scheduler="$(runner_resolve_scheduler "$scheduler")" || return $?
    runner_build_scheduled_command "$scheduler" "$cpus" "$x11" 1 "${launch_args[@]}"
    runner_info "Opening waveform: $open_file"
    (cd "$launch_dir" && "${RUNNER_COMMAND[@]}") &
}

runner_wave_show_text() {
    local file="$1" show_all="$2" tail_lines="$3" open_text="$4" viewer="$5"
    [[ -f "$file" ]] || { runner_die "Text artifact not found: $file"; return $?; }
    if ((open_text)); then
        [[ -n "$viewer" ]] || viewer="${TEXT_VIEWER:-less}"
        read -r -a viewer_args <<< "$viewer"; "${viewer_args[@]}" "$file"
    elif ((show_all)); then
        cat "$file"
    else
        tail -n "$tail_lines" "$file"
    fi
}

runner_open_wave() {
    local mode='list' identifier='' format='any' viewer=''
    local scheduler="${DV_VIEW_SCHEDULER:-${DV_DEFAULT_SCHEDULER:-local}}"
    local cpus="${DV_VIEW_CPUS:-1}" x11="${DV_VIEW_X11:-0}"
    local source_mode="${DV_VERDI_SOURCE_MODE:-auto}"
    local test_name='' seed='' tail_lines=80 show_all=0 open_dump=0 open_text=0 limit=20 file='' show_help=0
    while (($#)); do
        case "$1" in
            -h|--help) show_help=1; shift ;;
            --file) file="$2"; identifier="$2"; mode='dump'; shift 2 ;;
            -d|--d|--dump) mode='dump'; if [[ -n "${2:-}" && "${2:0:1}" != '-' ]]; then identifier="$2"; shift 2; else shift; fi ;;
            -l|--l|--log) mode='log'; if [[ -n "${2:-}" && "${2:0:1}" != '-' ]]; then identifier="$2"; shift 2; else shift; fi ;;
            -c|--c|--compile) mode='compile'; if [[ -n "${2:-}" && "${2:0:1}" != '-' ]]; then identifier="$2"; shift 2; else shift; fi ;;
            -o|--open|--run) open_dump=1; if [[ -n "${2:-}" && "${2:0:1}" != '-' ]]; then identifier="$2"; shift 2; else shift; fi ;;
            --open-log|--open-compile) open_text=1; shift ;;
            --format|--wave-format|--dump-format) format="${2,,}"; shift 2 ;;
            --fsdb) format='fsdb'; shift ;;
            --vcd) format='vcd'; shift ;;
            --vpd) format='vpd'; shift ;;
            --any-dump) format='any'; shift ;;
            --last) identifier='last'; shift ;;
            -t|--test) test_name="$2"; shift 2 ;;
            -s|--seed) seed="$2"; shift 2 ;;
            --viewer|-v) viewer="$2"; shift 2 ;;
            --source-map) source_mode="${2,,}"; shift 2 ;;
            --no-source-map) source_mode=off; shift ;;
            --tail) if [[ -n "${2:-}" && "$2" =~ ^[0-9]+$ ]]; then tail_lines="$2"; shift 2; else shift; fi ;;
            --show-log|--show-compile|--show) show_all=1; shift ;;
            --limit) limit="$2"; shift 2 ;;
            --scheduler) scheduler="$2"; shift 2 ;;
            --cpus) cpus="$2"; shift 2 ;;
            --x11) x11=1; shift ;;
            --no-x11) x11=0; shift ;;
            *) runner_die "Unknown view/wave option: $1"; return $? ;;
        esac
    done
    case "$format" in any|fsdb|vcd|vpd) ;; *) runner_die "Invalid wave format: $format"; return $?;; esac
    case "$source_mode" in auto|off|reparse) ;; *) runner_die "Invalid source-map mode: $source_mode"; return $?;; esac
    case "$x11" in 0|1) ;; *) runner_die "DV_VIEW_X11 must be 0 or 1: $x11"; return $?;; esac
    if ((show_help)); then runner_wave_print_guide; return; fi
    runner_require_uint --limit "$limit" || return $?; runner_require_uint --tail "$tail_lines" || return $?
    [[ -z "$seed" || -n "$test_name" ]] || { runner_die "--seed requires --test"; return $?; }

    if [[ "$mode" == list && "$open_dump" == 0 ]]; then
        runner_wave_print_guide
        printf '\nAvailable waveform artifacts:\n'
        runner_wave_list "$format" "$limit"
        return
    fi
    if [[ "$mode" == log || "$mode" == compile ]]; then
        local text_file
        text_file="$(runner_wave_find_log "$mode" "$identifier" "$test_name" "$seed")" || { runner_die "Requested log was not found"; return $?; }
        runner_wave_show_text "$text_file" "$show_all" "$tail_lines" "$open_text" "$viewer"
        return
    fi
    local wave_file
    if [[ -n "$file" && -f "$file" ]]; then wave_file="$file"; else wave_file="$(runner_wave_find "$format" "$identifier" "$test_name" "$seed")" || true; fi
    [[ -n "$wave_file" ]] || { runner_die "Requested waveform was not found"; return $?; }
    printf 'Wave Dump   : %s\nWave Format : %s\n' "$wave_file" "${wave_file##*.}"
    local mapped; mapped="$(runner_wave_mapped_log "$wave_file")"; [[ -n "$mapped" ]] && printf 'Mapped Log  : %s\n' "$mapped"
    ((open_dump)) && runner_wave_open_dump "$wave_file" "$viewer" "$scheduler" "$cpus" "$x11" "$source_mode"
}
