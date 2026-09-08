#!/usr/bin/env bash

runner_wave_print_guide() {
    local example_test="${DV_HELP_EXAMPLE_TEST:-smoke_test}"
    local waiver_example="${DV_HELP_COV_WAIVER_FILE:-sim/scripts/coverage_filter.el}"
    cat <<EOF
Wave, Coverage, And Log Viewer

List/open waveform dumps, merged coverage databases, and matching logs.

Options:
  select : --dump, --log, --compile, --file, --last
  runs   : --runs, --run-id RUN_ID, --latest-run
  filter : --test, --seed, --format, --fsdb, --vcd, --vpd, --limit
  action : --open, --tail, --show-log, --show-compile, --open-log, --open-compile
  viewer : --viewer, --source-map auto|off|reparse, --scheduler, --cpus, --x11
  cov    : --coverage, --variant auto|raw|adjusted, --elfile FILE

Examples:
  ./run.sh view --any-dump --limit 10
  ./run.sh view --runs --limit 10
  ./run.sh view --run-id <RUN_ID> --fsdb
  ./run.sh view --latest-run --fsdb
  ./run.sh view --open --last --fsdb
  ./run.sh view --open --last --fsdb --source-map reparse
  ./run.sh view --open --last --test $example_test --seed 1 --fsdb
  ./run.sh view --log --last --test $example_test --seed 1 --tail 120
  ./run.sh view --compile --last --show-compile
  ./run.sh view --coverage --runs
  ./run.sh view --coverage --run-id <RUN_ID>
  ./run.sh view --coverage --latest-run --open
  ./run.sh view --coverage --run-id <RUN_ID> --variant raw --open
  ./run.sh view --coverage --run-id <RUN_ID> --open --elfile $waiver_example

Coverage viewers always run through Slurm with X11 and the exported tool environment.
Read docs/user-guide/REFERENCE_RUNNER.md for artifact and source-mapping contracts.
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

runner_view_latest_run_id() {
    local runs_dir
    runs_dir="$(runner_runs_dir)"
    [[ -d "$runs_dir" ]] || return 1
    find "$runs_dir" -mindepth 1 -maxdepth 1 -type d -printf '%T@|%f\n' 2>/dev/null |
        sort -t'|' -k1,1nr | head -n 1 | cut -d'|' -f2-
}

runner_view_meta_value() {
    local file="$1" key="$2"
    [[ -r "$file" ]] || return 1
    awk -F= -v key="$key" '$1 == key {print substr($0, index($0, "=") + 1); exit}' "$file"
}

runner_view_run_status() {
    local run_dir="$1" file status
    for file in "$run_dir/summary/signoff.log" "$run_dir/summary/regression.log" \
                "$run_dir/summary/test.log" "$run_dir/summary/compile.log"; do
        [[ -r "$file" ]] || continue
        status="$(awk '/^[[:space:]]*Status[[:space:]]*:/ {print $3; exit}' "$file")"
        [[ -z "$status" ]] || { printf '%s\n' "$status"; return; }
    done
    if grep -R -q --include='status.tsv' --include='case_status.tsv' '|FAIL|' "$run_dir" 2>/dev/null; then
        printf 'FAIL\n'
    elif grep -R -q --include='status.tsv' --include='case_status.tsv' '|PASS|' "$run_dir" 2>/dev/null; then
        printf 'PASS\n'
    elif [[ -r "$run_dir/metadata/manifest.tsv" || -r "$run_dir/manifest.tsv" ]]; then
        printf 'PLANNED\n'
    else
        printf 'UNKNOWN\n'
    fi
}

runner_view_list_runs() {
    local limit="$1" count=0 entry run_dir run_id meta kind status tests waves vdbs created
    local runs_dir
    runs_dir="$(runner_runs_dir)"
    [[ -d "$runs_dir" ]] || { runner_info "No run history found under $runs_dir"; return; }
    while IFS='|' read -r _ run_dir; do
        run_id="$(basename "$run_dir")"
        meta="$run_dir/metadata/run.meta"
        [[ -r "$meta" ]] || meta="$run_dir/run.meta"
        kind="$(runner_view_meta_value "$meta" kind 2>/dev/null || true)"
        [[ -n "$kind" ]] || kind="${run_id%%_*}"
        status="$(runner_view_run_status "$run_dir")"
        local manifest="$run_dir/metadata/manifest.tsv"
        [[ -r "$manifest" ]] || manifest="$run_dir/manifest.tsv"
        if [[ -r "$manifest" ]]; then
            tests="$(awk -F'|' 'NR>1 && $2!="" {seen[$2]=1} END {for (item in seen) count++; print count+0}' "$manifest")"
        else
            local tests_root="$run_dir/tests"
            [[ -d "$tests_root" ]] || tests_root="$run_dir/cases"
            tests="$(find "$tests_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
        fi
        waves="$(find "$run_dir" -type f \( -name '*.fsdb' -o -name '*.vcd' -o -name '*.vpd' \) 2>/dev/null | wc -l)"
        vdbs="$(find "$run_dir" -type d -name '*.vdb' 2>/dev/null | wc -l)"
        created="$(runner_view_meta_value "$meta" created 2>/dev/null || true)"
        count=$((count + 1))
        printf '[%d] %s\n' "$count" "$run_id"
        printf '    kind   : %s\n' "${kind:-unknown}"
        printf '    status : %s\n' "$status"
        printf '    tests  : %s\n' "$tests"
        printf '    wave   : %s\n' "$waves"
        printf '    vdb    : %s\n' "$vdbs"
        [[ -z "$created" ]] || printf '    created: %s\n' "$created"
        printf '%s\n' '-------------------------------------------------------------------------'
        ((count >= limit)) && break
    done < <(find "$runs_dir" -mindepth 1 -maxdepth 1 -type d -printf '%T@|%p\n' 2>/dev/null | sort -t'|' -k1,1nr)
    ((count > 0)) || runner_info "No run history found under $runs_dir"
}

runner_cov_database_candidates() {
    local cov_root relative run_id variant result_dir path
    cov_root="$(runner_out_dir)/coverage"
    [[ -d "$cov_root" ]] || return 0
    while IFS='|' read -r timestamp path; do
        relative="${path#"$cov_root/"}"
        if [[ "$relative" == */* ]]; then
            run_id="${relative%%/*}"
        else
            run_id="$(basename "$relative")"
            run_id="${run_id%.vdb}"
        fi
        variant=regular
        if [[ "/$relative/" == */raw/* ]]; then
            variant=raw
        else
            result_dir="$cov_root/$run_id"
            if [[ -r "$result_dir/waiver.meta" || -r "$(dirname "$path")/waiver.meta" ]]; then
                variant=adjusted
            fi
        fi
        printf '%s|%s|%s|%s\n' "$timestamp" "$run_id" "$variant" "$path"
    done < <(find "$cov_root" -type d \( -name 'merged.vdb' -o -name 'all.vdb' \) \
        -printf '%T@|%p\n' 2>/dev/null)
}

runner_cov_report_for_database() {
    local database="$1" base candidate
    base="$(dirname "$database")"
    for candidate in "$base/report/dashboard.html" "$base/report/hierarchy.html"; do
        [[ -r "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
    done
    return 1
}

runner_cov_list_databases() {
    local limit="$1" identifier="$2" requested_variant="$3"
    local count=0 timestamp run_id variant database report
    while IFS='|' read -r timestamp run_id variant database; do
        [[ -z "$identifier" || "$run_id" == "$identifier" || "$database" == *"$identifier"* ]] || continue
        [[ "$requested_variant" == auto || "$variant" == "$requested_variant" ]] || continue
        count=$((count + 1))
        report="$(runner_cov_report_for_database "$database" 2>/dev/null || true)"
        printf '[%d] COV  run=%s  variant=%s\n' "$count" "$run_id" "$variant"
        printf '    database: %s\n' "$(runner_wave_display_path "$database")"
        [[ -z "$report" ]] || printf '    report  : %s\n' "$(runner_wave_display_path "$report")"
        printf '%s\n' '-------------------------------------------------------------------------'
        ((count >= limit)) && break
    done < <(runner_cov_database_candidates | sort -t'|' -k1,1nr)
    ((count > 0)) || runner_info "No merged coverage databases found under $(runner_out_dir)/coverage"
}

runner_cov_latest_run_id() {
    local requested_variant="$1" _ run_id variant _database
    while IFS='|' read -r _ run_id variant _database; do
        [[ "$requested_variant" == auto || "$variant" == "$requested_variant" ]] || continue
        printf '%s\n' "$run_id"
        return 0
    done < <(runner_cov_database_candidates | sort -t'|' -k1,1nr)
    return 1
}

runner_cov_find_database() {
    local identifier="$1" requested_variant="$2" explicit_file="$3"
    local preferred _ run_id variant database
    if [[ -n "$explicit_file" ]]; then
        [[ "$explicit_file" == /* ]] || explicit_file="$RUNNER_ROOT/$explicit_file"
        [[ -d "$explicit_file" ]] || return 1
        printf '%s\n' "$explicit_file"
        return 0
    fi
    for preferred in $([[ "$requested_variant" == auto ]] && printf 'adjusted regular raw' || printf '%s' "$requested_variant"); do
        while IFS='|' read -r _ run_id variant database; do
            [[ "$variant" == "$preferred" ]] || continue
            [[ -z "$identifier" || "$run_id" == "$identifier" || "$database" == *"$identifier"* ]] || continue
            printf '%s\n' "$database"
            return 0
        done < <(runner_cov_database_candidates | sort -t'|' -k1,1nr)
    done
    return 1
}

runner_cov_variant_for_database() {
    local target="$1" _ _run_id variant database
    while IFS='|' read -r _ _run_id variant database; do
        [[ "$database" == "$target" ]] || continue
        printf '%s\n' "$variant"
        return 0
    done < <(runner_cov_database_candidates)
    printf 'explicit\n'
}

runner_cov_view_work_dir() {
    local run_id="${1:-coverage_view}" token
    token="$(runner_sanitize_token "$run_id")"
    printf '%s/view/coverage/%s\n' "$(runner_out_dir)" "$token"
}

runner_cov_open_database() {
    local database="$1" viewer="$2" cpus="$3" elfile="$4" run_id="$5"
    local view_work_dir
    local -a viewer_args launch_args
    [[ -n "$viewer" ]] || viewer="${COV_VIEWER:-verdi}"
    read -r -a viewer_args <<< "$viewer"
    ((${#viewer_args[@]} > 0)) || { runner_die "Coverage viewer command is empty"; return $?; }
    launch_args=("${viewer_args[@]}" -cov -covdir "$database")
    if [[ -n "$elfile" ]]; then
        [[ "$elfile" == /* ]] || elfile="$RUNNER_ROOT/$elfile"
        [[ -r "$elfile" ]] || { runner_die "Coverage exclusion file is not readable: $elfile"; return $?; }
        launch_args+=(-elfile "$elfile")
    fi
    RUNNER_ACTIVE_RUN_ID="${run_id:-coverage_view}"
    RUNNER_ACTIVE_TEST=coverage-view
    view_work_dir="$(runner_cov_view_work_dir "$RUNNER_ACTIVE_RUN_ID")"
    mkdir -p "$view_work_dir"
    {
        printf 'run_id=%s\n' "$RUNNER_ACTIVE_RUN_ID"
        printf 'database=%s\n' "$database"
        printf 'exclusion_file=%s\n' "${elfile:-none}"
        printf 'created=%s\n' "$(date -Is)"
    } > "$view_work_dir/coverage_view.meta"
    RUNNER_SLURM_EXPORT=ALL runner_build_scheduled_command slurm "$cpus" 1 0 "${launch_args[@]}" || return $?
    runner_info "Opening coverage through Slurm/X11: $(runner_wave_display_path "$database")"
    runner_info "Coverage viewer workspace: $(runner_wave_display_path "$view_work_dir")"
    (cd "$view_work_dir" && "${RUNNER_COMMAND[@]}") &
}

runner_wave_list() {
    local format="$1" limit="$2" identifier="${3:-}" filter_test="${4:-}" filter_seed="${5:-}"
    local count=0 path mapped display_wave display_log
    local run_id test_name seed attempt extension stem
    while IFS='|' read -r _ path; do
        [[ -z "$identifier" || "$identifier" == last || "$path" == *"/runs/$identifier/"* ]] || continue
        [[ -z "$filter_test" || "$path" == *"/$filter_test/"* || "$path" == *"$filter_test"* ]] || continue
        [[ -z "$filter_seed" || "$path" == *"seed_${filter_seed}"* ]] || continue
        count=$((count + 1))
        run_id='unknown'; test_name='unknown'; seed='?'; attempt='-'
        extension="${path##*.}"; extension="${extension^^}"
        if [[ "$path" =~ /runs/([^/]+)/(tests|cases)/([^/]+)/seed_([^/]+)/attempt_([0-9]+)/dumps/ ]]; then
            run_id="${BASH_REMATCH[1]}"
            test_name="${BASH_REMATCH[3]}"
            seed="${BASH_REMATCH[4]}"
            printf -v attempt 'A%03d' "$((10#${BASH_REMATCH[5]}))"
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
        if [[ -r "$current/metadata/compile.meta" ]]; then
            printf '%s\n' "$current/metadata/compile.meta"
            return 0
        fi
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
    local list_runs=0 latest_run=0 coverage_mode=0 coverage_variant=auto coverage_elfile=''
    local scheduler_explicit=0 no_x11_requested=0
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
            --runs|--list-runs) list_runs=1; shift ;;
            --run-id) identifier="$2"; shift 2 ;;
            --latest-run) latest_run=1; shift ;;
            --coverage|--cov-db) coverage_mode=1; shift ;;
            --variant|--coverage-variant) coverage_variant="${2,,}"; shift 2 ;;
            --elfile|--exclusion-file) coverage_elfile="$2"; shift 2 ;;
            -t|--test) test_name="$2"; shift 2 ;;
            -s|--seed) seed="$2"; shift 2 ;;
            --viewer|-v) viewer="$2"; shift 2 ;;
            --source-map) source_mode="${2,,}"; shift 2 ;;
            --no-source-map) source_mode=off; shift ;;
            --tail) if [[ -n "${2:-}" && "$2" =~ ^[0-9]+$ ]]; then tail_lines="$2"; shift 2; else shift; fi ;;
            --show-log|--show-compile|--show) show_all=1; shift ;;
            --limit) limit="$2"; shift 2 ;;
            --scheduler) scheduler="$2"; scheduler_explicit=1; shift 2 ;;
            --cpus) cpus="$2"; shift 2 ;;
            --x11) x11=1; shift ;;
            --no-x11) x11=0; no_x11_requested=1; shift ;;
            *) runner_die "Unknown view/wave option: $1"; return $? ;;
        esac
    done
    case "$format" in any|fsdb|vcd|vpd) ;; *) runner_die "Invalid wave format: $format"; return $?;; esac
    case "$source_mode" in auto|off|reparse) ;; *) runner_die "Invalid source-map mode: $source_mode"; return $?;; esac
    case "$coverage_variant" in auto|raw|adjusted) ;; *) runner_die "Invalid coverage variant: $coverage_variant"; return $?;; esac
    case "$x11" in 0|1) ;; *) runner_die "DV_VIEW_X11 must be 0 or 1: $x11"; return $?;; esac
    if ((show_help)); then runner_wave_print_guide; return; fi
    runner_require_uint --limit "$limit" || return $?; runner_require_uint --tail "$tail_lines" || return $?
    runner_require_uint --cpus "$cpus" || return $?
    [[ -z "$seed" || -n "$test_name" ]] || { runner_die "--seed requires --test"; return $?; }

    if ((coverage_mode)); then
        [[ "$mode" != log && "$mode" != compile ]] || {
            runner_die "--coverage cannot be combined with log or compile selection"
            return $?
        }
        [[ -z "$test_name" && -z "$seed" ]] || {
            runner_die "--test and --seed do not select merged coverage databases"
            return $?
        }
        if ((scheduler_explicit)) && [[ "$scheduler" != slurm ]]; then
            runner_die "Coverage viewing is Slurm-only; use --scheduler slurm"
            return $?
        fi
        if ((open_dump && no_x11_requested)); then
            runner_die "Coverage viewing requires Slurm X11; remove --no-x11"
            return $?
        fi
        if ((latest_run)) || ((open_dump)) && [[ -z "$identifier" && -z "$file" ]]; then
            identifier="$(runner_cov_latest_run_id "$coverage_variant")" || {
                runner_die "No merged coverage database was found"
                return $?
            }
        fi
        if ((list_runs)) || ((open_dump == 0)); then
            runner_cov_list_databases "$limit" "$identifier" "$coverage_variant"
            return
        fi
        local coverage_database coverage_report coverage_actual_variant
        coverage_database="$(runner_cov_find_database "$identifier" "$coverage_variant" "$file")" || {
            runner_die "Merged coverage database was not found for run=${identifier:-latest} variant=$coverage_variant"
            return $?
        }
        coverage_report="$(runner_cov_report_for_database "$coverage_database" 2>/dev/null || true)"
        coverage_actual_variant="$(runner_cov_variant_for_database "$coverage_database")"
        printf 'Coverage DB : %s\n' "$(runner_wave_display_path "$coverage_database")"
        printf 'Variant     : %s\n' "$coverage_actual_variant"
        [[ -z "$coverage_report" ]] || printf 'Report      : %s\n' "$(runner_wave_display_path "$coverage_report")"
        [[ -z "$coverage_elfile" ]] || printf 'Exclusion   : %s\n' "$coverage_elfile"
        runner_cov_open_database "$coverage_database" "$viewer" "$cpus" "$coverage_elfile" "$identifier"
        return
    fi

    if ((list_runs)); then runner_view_list_runs "$limit"; return; fi
    if ((latest_run)); then
        identifier="$(runner_view_latest_run_id)" || { runner_die "No run history found"; return $?; }
    fi

    if [[ "$mode" == list && "$open_dump" == 0 ]]; then
        runner_wave_print_guide
        printf '\nAvailable waveform artifacts:\n'
        runner_wave_list "$format" "$limit" "$identifier" "$test_name" "$seed"
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
