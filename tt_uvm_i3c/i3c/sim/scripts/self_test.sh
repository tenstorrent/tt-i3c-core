#!/usr/bin/env bash

runner_self_test_assert() {
    local condition="$1" message="$2"
    if ! eval "$condition"; then runner_error "Self-test assertion failed: $message"; return 1; fi
}

runner_self_test() (
    local self_test_root
    self_test_root="$(mktemp -d)" || return 1
    export RUNNER_OUT_DIR="$self_test_root/out"
    trap '[[ -z "${self_test_root:-}" ]] || rm -rf "$self_test_root"' EXIT

    runner_info "Starting tool-independent runner self-test"
    # The runner qualification suite uses dry-run fixtures and must not require
    # a native RTL source root or simulator installation.
    [[ -d "$(runner_out_dir)" ]] && runner_clean --all || true
    # A configured project preflight intentionally checks native RTL, Caliptra,
    # and simulator availability.  Those are outside this tool-independent
    # fixture suite; generic config/schema checks still run below.
    runner_project_preflight() { return 0; }
    runner_check_config || return $?

    local report_project_prefix="${RUNNER_ROOT#"$RUNNER_REPORT_ROOT/"}"
    runner_self_test_assert "[[ \"\$(runner_report_path '$RUNNER_ROOT/sim/out/runs/example/logs/sim.log')\" == '$report_project_prefix/sim/out/runs/example/logs/sim.log' ]]" \
        "package reports paths relative to the public root entry point" || return $?
    runner_self_test_assert "[[ \"\$(runner_report_path '/tmp/external-example.log')\" == '/tmp/external-example.log' ]]" \
        "paths outside the package remain absolute" || return $?
    runner_self_test_assert "[[ \"\$(runner_html_escape '<tag a=\"x\">&')\" == '&lt;tag a=&quot;x&quot;&gt;&amp;' ]]" \
        "HTML summaries escape untrusted labels" || return $?

    local summary_fail_fixture summary_fail_output summary_help_output summary_index_output
    summary_fail_fixture="$self_test_root/summary-fail"
    mkdir -p "$summary_fail_fixture/summary" "$summary_fail_fixture/logs"
    printf '%s\n' \
        "now|B001|A001|passing_test|pass_case|light||1|A001|PASS|0|PASS|1|$summary_fail_fixture/logs/pass.log|0|0|0|0|0|0" \
        "now|B002|A001|failing_test|fail_case|medium|+MODE=fail|2|A001|FAIL|1|UVM_FAIL|2|$summary_fail_fixture/logs/fail.log|0|1|0|0|0|1" \
        > "$summary_fail_fixture/summary/regression.cases.latest.tsv"
    summary_fail_output="$(runner_show_failed_tests "$summary_fail_fixture")" || return $?
    runner_self_test_assert "[[ \$(grep -c '^Test :' <<< \"\$summary_fail_output\") -eq 1 ]]" \
        "fail-only summary prints one entry per failed case" || return $?
    runner_self_test_assert "grep -q '^Test : failing_test$' <<< \"\$summary_fail_output\" && grep -Fq 'Log  : $summary_fail_fixture/logs/fail.log' <<< \"\$summary_fail_output\"" \
        "fail-only summary prints the failed test and detail log" || return $?
    runner_self_test_assert "! grep -q 'passing_test\|pass.log' <<< \"\$summary_fail_output\"" \
        "fail-only summary excludes passing tests" || return $?
    summary_help_output="$(runner_print_help summary)" || return $?
    runner_self_test_assert "grep -q -- '--fail, --failures' <<< \"\$summary_help_output\"" \
        "summary help documents fail-only output" || return $?
    runner_self_test_assert "grep -q -- '--html' <<< \"\$summary_help_output\"" \
        "summary help documents the HTML dashboard" || return $?
    mkdir -p "$(runner_runs_dir)/summary_regression/summary" \
        "$(runner_runs_dir)/summary_coverage/summary"
    : > "$(runner_runs_dir)/summary_regression/summary/regression.log"
    : > "$(runner_runs_dir)/summary_regression/summary/regression.errors.log"
    : > "$(runner_runs_dir)/summary_regression/summary/artifacts.tsv"
    : > "$(runner_runs_dir)/summary_coverage/summary/regression.log"
    : > "$(runner_runs_dir)/summary_coverage/summary/failures.log"
    : > "$(runner_runs_dir)/summary_coverage/summary/coverage.log"
    : > "$(runner_runs_dir)/summary_coverage/summary/artifacts.tsv"
    summary_index_output="$(runner_list_summary_indexes '' 2)" || return $?
    runner_self_test_assert "[[ \$(grep -c '^Run ID:' <<< \"\$summary_index_output\") -eq 2 && \$(grep -c $'^\\t' <<< \"\$summary_index_output\") -eq 8 ]]" \
        "summary index prints two Run IDs with four indented paths each" || return $?
    runner_self_test_assert "grep -q 'summary_regression/summary/regression.log' <<< \"\$summary_index_output\" && grep -q 'summary_coverage/summary/coverage.log' <<< \"\$summary_index_output\" && grep -q 'summary_coverage/summary/failures.log' <<< \"\$summary_index_output\"" \
        "summary index handles regression and coverage layouts" || return $?
    runner_self_test_assert "grep -q $'^\\tCoverage : -$' <<< \"\$summary_index_output\"" \
        "summary index marks unavailable artifact classes" || return $?
    local summary_html_output
    summary_html_output="$(runner_show_summary --id summary_regression --html)" || return $?
    runner_self_test_assert "grep -q '^HTML Summary: .*summary_regression/summary/run_summary.html$' <<< \"\$summary_html_output\"" \
        "summary --html generates and locates a per-run dashboard" || return $?

    local fsdb_plan_root fsdb_integrated_plan fsdb_legacy_plan vcd_plan vpd_plan none_plan cov_plan serial_plan assert_quiet_plan waiver_merge_plan
    fsdb_plan_root="$self_test_root/fsdb-plan"
    mkdir -p "$fsdb_plan_root"
    fsdb_integrated_plan="$(
        make -s -f "$RUNNER_SCRIPT_DIR/vcs_backend.mk" comp \
            DRY_RUN=1 UVM_MODE=builtin FILELIST=/dev/null TOP=tb_top EXTRA_COMPILE_OPTS= \
            BUILD_DIR="$fsdb_plan_root/build" LOG_DIR="$fsdb_plan_root/logs" \
            COV_DIR="$fsdb_plan_root/cov" DUMP_DIR="$fsdb_plan_root/dumps" \
            STATE_DIR="$fsdb_plan_root/state" RUNS_DIR="$fsdb_plan_root/runs" \
            DUMP_FORMAT=fsdb DV_FSDB_DEFINE=FSDB_SELFTEST \
            DV_FSDB_COMPILE_STYLE=integrated VERDI_HOME=/opt/mock-verdi
    )" || return $?
    runner_self_test_assert "grep -q -- '-debug_access+all' <<< \"\$fsdb_integrated_plan\"" \
        "integrated FSDB uses debug_access" || return $?
    runner_self_test_assert "grep -q -- '-kdb -debug_access+all' <<< \"\$fsdb_integrated_plan\"" \
        "integrated FSDB creates the Verdi debug database" || return $?
    runner_self_test_assert "! grep -q -- ' -P ' <<< \"\$fsdb_integrated_plan\"" \
        "integrated FSDB does not load legacy PLI" || return $?

    fsdb_legacy_plan="$(
        make -s -f "$RUNNER_SCRIPT_DIR/vcs_backend.mk" comp \
            DRY_RUN=1 UVM_MODE=builtin FILELIST=/dev/null TOP=tb_top EXTRA_COMPILE_OPTS= \
            BUILD_DIR="$fsdb_plan_root/build" LOG_DIR="$fsdb_plan_root/logs" \
            COV_DIR="$fsdb_plan_root/cov" DUMP_DIR="$fsdb_plan_root/dumps" \
            STATE_DIR="$fsdb_plan_root/state" RUNS_DIR="$fsdb_plan_root/runs" \
            DUMP_FORMAT=fsdb DV_FSDB_DEFINE=FSDB_SELFTEST \
            DV_FSDB_COMPILE_STYLE=legacy FSDB_PLI_DIR=/opt/mock-pli
    )" || return $?
    runner_self_test_assert "grep -q -- '-P /opt/mock-pli/novas.tab /opt/mock-pli/pli.a' <<< \"\$fsdb_legacy_plan\"" \
        "legacy FSDB retains explicit PLI loading" || return $?

    vpd_plan="$(
        make -s -f "$RUNNER_SCRIPT_DIR/vcs_backend.mk" comp \
            DRY_RUN=1 UVM_MODE=builtin FILELIST=/dev/null TOP=tb_top EXTRA_COMPILE_OPTS= \
            BUILD_DIR="$fsdb_plan_root/build" LOG_DIR="$fsdb_plan_root/logs" \
            COV_DIR="$fsdb_plan_root/cov" DUMP_DIR="$fsdb_plan_root/dumps" \
            STATE_DIR="$fsdb_plan_root/state" RUNS_DIR="$fsdb_plan_root/runs" \
            DUMP_FORMAT=vpd DV_VPD_DEFINE=VPD_SELFTEST
    )" || return $?
    runner_self_test_assert "grep -q -- '+define+VPD_SELFTEST -debug_access+all' <<< \"\$vpd_plan\"" \
        "VPD compile enables only its guarded system tasks" || return $?

    vcd_plan="$(
        make -s -f "$RUNNER_SCRIPT_DIR/vcs_backend.mk" comp \
            DRY_RUN=1 UVM_MODE=builtin FILELIST=/dev/null TOP=tb_top EXTRA_COMPILE_OPTS= \
            BUILD_DIR="$fsdb_plan_root/build" LOG_DIR="$fsdb_plan_root/logs" \
            COV_DIR="$fsdb_plan_root/cov" DUMP_DIR="$fsdb_plan_root/dumps" \
            STATE_DIR="$fsdb_plan_root/state" RUNS_DIR="$fsdb_plan_root/runs" \
            DUMP_FORMAT=vcd DV_VCD_DEFINE=VCD_SELFTEST
    )" || return $?
    runner_self_test_assert "grep -q -- '+define+VCD_SELFTEST' <<< \"\$vcd_plan\"" \
        "VCD compile enables only its guarded system tasks" || return $?

    none_plan="$(
        make -s -f "$RUNNER_SCRIPT_DIR/vcs_backend.mk" comp \
            DRY_RUN=1 UVM_MODE=builtin FILELIST=/dev/null TOP=tb_top EXTRA_COMPILE_OPTS= \
            BUILD_DIR="$fsdb_plan_root/build" LOG_DIR="$fsdb_plan_root/logs" \
            COV_DIR="$fsdb_plan_root/cov" DUMP_DIR="$fsdb_plan_root/dumps" \
            STATE_DIR="$fsdb_plan_root/state" RUNS_DIR="$fsdb_plan_root/runs" \
            DUMP_FORMAT=none
    )" || return $?
    runner_self_test_assert "! grep -q -- '-debug_access' <<< \"\$none_plan\"" \
        "no-dump compile has no waveform instrumentation" || return $?
    runner_self_test_assert "! grep -q -- '+define+VCD_SELFTEST' <<< \"\$none_plan\"" \
        "no-dump compile does not enable VCD system tasks" || return $?
    runner_self_test_assert "grep -q -- ' -j4 ' <<< \"\$none_plan\"" \
        "VCS compile defaults to four parallel processes" || return $?
    cov_plan="$(
        make -s -f "$RUNNER_SCRIPT_DIR/vcs_backend.mk" comp \
            DRY_RUN=1 UVM_MODE=builtin FILELIST=/dev/null TOP=tb_top COV=1 EXTRA_COMPILE_OPTS= \
            BUILD_DIR="$fsdb_plan_root/build" LOG_DIR="$fsdb_plan_root/logs" \
            COV_DIR="$fsdb_plan_root/cov" DUMP_DIR="$fsdb_plan_root/dumps" \
            STATE_DIR="$fsdb_plan_root/state" RUNS_DIR="$fsdb_plan_root/runs" \
            DUMP_FORMAT=none
    )" || return $?
    runner_self_test_assert "grep -q -- '-cm assert -cm_assert_hier .*sim/scripts/cov_setup.cfg' <<< \"\$cov_plan\"" \
        "coverage compile selects IBI assertion metrics and applies the hierarchy filter" || return $?
    runner_self_test_assert "! grep -Eq -- '-cm [^ ]*(line|cond|tgl|fsm|branch)' <<< \"\$cov_plan\"" \
        "IBI coverage compile disables RTL code metrics" || return $?
    cov_merge_plan="$(
        make -s -f "$RUNNER_SCRIPT_DIR/vcs_backend.mk" merge-cov \
            DRY_RUN=1 UVM_MODE=builtin COV_DIR="$fsdb_plan_root/cov" \
            COV_INPUTS="$fsdb_plan_root/cov/input.vdb"
    )" || return $?
    runner_self_test_assert "grep -q -- '-hier .*sim/scripts/cov_setup.cfg' <<< \"\$cov_merge_plan\"" \
        "coverage report applies the IBI hierarchy filter" || return $?
    runner_self_test_assert "grep -q -- '-group db_edit_file .*sim/scripts/ibi_group_db_edit.cfg' <<< \"\$cov_merge_plan\"" \
        "coverage merge removes the non-IBI RTL covergroup" || return $?
    assert_quiet_plan="$(
        make -s -f "$RUNNER_SCRIPT_DIR/vcs_backend.mk" run \
            DRY_RUN=1 UVM_MODE=builtin TEST=assert_quiet_test SEED=1 \
            BUILD_DIR="$fsdb_plan_root/build" LOG_DIR="$fsdb_plan_root/logs" \
            COV_DIR="$fsdb_plan_root/cov" DUMP_DIR="$fsdb_plan_root/dumps" \
            STATE_DIR="$fsdb_plan_root/state" RUNS_DIR="$fsdb_plan_root/runs" \
            DUMP_FORMAT=none
    )" || return $?
    runner_self_test_assert "grep -q -- '-assert quiet' <<< \"\$assert_quiet_plan\"" \
        "VCS runtime suppresses the end-of-run assertion dump by default" || return $?
    serial_plan="$(
        make -s -f "$RUNNER_SCRIPT_DIR/vcs_backend.mk" comp \
            DRY_RUN=1 UVM_MODE=builtin FILELIST=/dev/null TOP=tb_top COMPILE_JOBS=1 EXTRA_COMPILE_OPTS= \
            BUILD_DIR="$fsdb_plan_root/build" LOG_DIR="$fsdb_plan_root/logs" \
            COV_DIR="$fsdb_plan_root/cov" DUMP_DIR="$fsdb_plan_root/dumps" \
            STATE_DIR="$fsdb_plan_root/state" RUNS_DIR="$fsdb_plan_root/runs" \
            DUMP_FORMAT=none
    )" || return $?
    runner_self_test_assert "! grep -Eq -- '(^|[[:space:]])-j[0-9]+' <<< \"\$serial_plan\"" \
        "single-process compile omits the VCS parallel option" || return $?
    waiver_merge_plan="$(
        make -s -f "$RUNNER_SCRIPT_DIR/vcs_backend.mk" merge-cov \
            DRY_RUN=1 COV_DIR="$fsdb_plan_root/waiver-cov" \
            COV_INPUTS='/tmp/compile.vdb /tmp/test.vdb' COV_WAIVER_FILE=/tmp/reviewed.el
    )" || return $?
    runner_self_test_assert "grep -q -- '-elfile \"/tmp/reviewed.el\"' <<< \"\$waiver_merge_plan\"" \
        "coverage waiver is passed explicitly to URG" || return $?
    runner_self_test_assert "grep -q -- '-dbname \"$fsdb_plan_root/waiver-cov/merged\"' <<< \"\$waiver_merge_plan\"" \
        "merged coverage database stays in the selected output directory" || return $?

    local compile_requirement_plan="$self_test_root/compile-requirements.dv"
    cat > "$compile_requirement_plan" <<'EOF'
# DV_TESTPLAN_VERSION=1
# test|group|level|enabled|seed_policy|default_seeds|plusargs|tags|compile_requirements
ordinary_test|smoke|light|on|all|1||generated|
hdl_test|special|light|on|all|1||generated|hdl_access
EOF
    local saved_test_list_file="${TEST_LIST_FILE:-}" requirement requirement_opts
    TEST_LIST_FILE="$compile_requirement_plan"
    requirement="$(runner_test_compile_requirements hdl_test)"
    requirement_opts="$(runner_test_compile_options "$requirement")" || return $?
    runner_self_test_assert "[[ \"\$requirement\" == hdl_access ]]" \
        "test plan exposes the HDL-access compile requirement" || return $?
    runner_self_test_assert "[[ \"\$requirement_opts\" == -debug_access+all ]]" \
        "HDL-access requirement maps to the VCS debug option" || return $?
    runner_self_test_assert "[[ -z \"\$(runner_test_compile_requirements ordinary_test)\" ]]" \
        "ordinary tests do not inherit HDL access" || return $?
    TEST_LIST_FILE="$saved_test_list_file"

    local waiver_fixture="$self_test_root/waiver-inputs"
    mkdir -p "$waiver_fixture"
    printf '# placeholder only\n' > "$waiver_fixture/filter.el"
    printf 'W1|COND|1|rtl/example.sv|condition|reason|evidence|REVIEWED\n' > "$waiver_fixture/manifest.tsv"
    runner_self_test_assert "! runner_cov_validate_waiver_inputs '$waiver_fixture/filter.el' '$waiver_fixture/manifest.tsv' >/dev/null 2>&1" \
        "empty waiver exclusion file is rejected" || return $?
    printf 'EXCLUSION_RULE_FROM_VERDI\n' >> "$waiver_fixture/filter.el"
    runner_cov_validate_waiver_inputs "$waiver_fixture/filter.el" "$waiver_fixture/manifest.tsv" || return $?
    local waiver_lifecycle="$waiver_fixture/lifecycle" waiver_promoted="$waiver_fixture/promoted.el"
    runner_cov_create_waiver_candidate "$waiver_lifecycle" "$waiver_fixture/filter.el" \
        "$waiver_fixture/manifest.tsv" || return $?
    runner_cov_check_waiver_candidate "$waiver_lifecycle" "$waiver_promoted" \
        "$waiver_fixture/manifest.tsv" || return $?
    runner_cov_promote_waiver_candidate "$waiver_lifecycle" "$waiver_promoted" \
        "$waiver_fixture/manifest.tsv" || return $?
    runner_self_test_assert "grep -Fq 'EXCLUSION_RULE_FROM_VERDI' '$waiver_promoted'" \
        "reviewed waiver candidate can be promoted to the canonical file" || return $?
    if declare -F dv_project_self_test >/dev/null 2>&1; then
        dv_project_self_test "$fsdb_plan_root/project-dump" || return $?
    fi

    local testlist_fixture="$self_test_root/testlist-project"
    mkdir -p "$testlist_fixture/sim/filelists" \
             "$testlist_fixture/verify/tb/tests" \
             "$testlist_fixture/rtl"
    : > "$testlist_fixture/verify/tb/tests/enabled_test.sv"
    : > "$testlist_fixture/verify/tb/tests/disabled_test.sv"
    cat > "$testlist_fixture/sim/filelists/test.f" <<'EOF'
sanity : light on {
enabled_test
# disabled_test
}
EOF
    if [[ -x "$RUNNER_SCRIPT_DIR/gen_mk_files.sh" ]]; then
        DV_RTL_ROOT="$testlist_fixture/rtl" \
            "$RUNNER_SCRIPT_DIR/gen_mk_files.sh" --root "$testlist_fixture" --test >/dev/null || return $?
        runner_self_test_assert \
            "grep -q '^enabled_test$' '$testlist_fixture/sim/filelists/test.f'" \
            "test-list generation preserves enabled tests" || return $?
        runner_self_test_assert \
            "grep -Eq '^[[:space:]]*#[[:space:]]*disabled_test[[:space:]]*$' '$testlist_fixture/sim/filelists/test.f'" \
            "commented tests remain explicitly disabled" || return $?
        runner_self_test_assert \
            "! grep -Eq '^[[:space:]]*disabled_test[[:space:]]*$' '$testlist_fixture/sim/filelists/test.f'" \
            "source discovery does not reactivate commented tests" || return $?
    fi

    local ansi_log="$(runner_out_dir)/self-test/ansi.log"
    mkdir -p "$(dirname "$ansi_log")"
    printf '\033[31mERROR\033[0m plain\n' > "$ansi_log"
    runner_sanitize_log_in_place "$ansi_log"
    runner_self_test_assert "! LC_ALL=C grep -q \$(printf '\\033') '$ansi_log' && grep -q '^ERROR plain$' '$ansi_log'" \
        "canonical logs are ANSI-free" || return $?
    local status_plain status_no_color
    status_plain="$(env -u NO_COLOR bash -c \
        "source '$RUNNER_SCRIPT_DIR/common.sh'; TERM=xterm runner_status_token PASS")"
    status_no_color="$(NO_COLOR=1 runner_status_token FAIL)"
    runner_self_test_assert \
        "[[ \"\$status_plain\" == '[PASS]' && \"\$status_no_color\" == '[FAIL]' ]]" \
        "redirected and NO_COLOR status tokens are ANSI-free" || return $?

    local completion_fixture completion_rc
    completion_fixture="$(mktemp -d)" || return 1
    completion_rc="$completion_fixture/bashrc"
    runner_completion_link_bash --rc-file "$completion_rc" >/dev/null || return $?
    runner_completion_link_bash --rc-file "$completion_rc" >/dev/null || return $?
    runner_self_test_assert "[[ \$(grep -c '^# >>> Generic DV Runner completion:' '$completion_rc') -eq 1 ]]" \
        "completion --link is idempotent" || return $?
    runner_self_test_assert "grep -Fq 'run_completion.bash' '$completion_rc'" \
        "completion --link installs the completion source" || return $?
    local completion_tests completion_expected
    completion_tests="$(runner_completion_command tests)"
    completion_expected="$(awk -F'|' '!/^[[:space:]]*#/ && NF {print $1; exit}' "$TEST_LIST_FILE")"
    runner_self_test_assert "grep -Fqx \"\$completion_expected\" <<< \"\$completion_tests\"" \
        "completion resolves generated test-plan entries" || return $?
    runner_self_test_assert "[[ -n \"\$(runner_completion_command cases)\" && -n \"\$(runner_completion_command groups)\" ]]" \
        "completion resolves per-entry cases and test-plan groups" || return $?
    runner_self_test_assert "grep -q -- '--case' '$RUNNER_SCRIPT_DIR/run_completion.bash' && grep -q -- '--waiver-promote' '$RUNNER_SCRIPT_DIR/run_completion.bash' && grep -q -- '--latest-run' '$RUNNER_SCRIPT_DIR/run_completion.bash'" \
        "linked completion exposes regression, waiver, and viewer options" || return $?
    rm -rf "$completion_fixture"

    local live_log live_output parent_output parent_activity_root
    live_log="$(runner_out_dir)/self-test/live/compile.log"
    live_output="$(
        export RUNNER_LIVE_MODE=line RUNNER_HEARTBEAT_SEC=1 RUNNER_NON_TTY_HEARTBEAT_SEC=1 COLUMNS=240
        export RUNNER_HANG_WARN_SEC=30 RUNNER_HANG_KILL_SEC=60 RUNNER_HANG_MIN_ELAPSED_SEC=30
        RUNNER_LIVE_PHASE=compile RUNNER_LIVE_ITEM='TEST=live_fixture' \
            runner_execute_logged live-fixture "$live_log" 10 0 0 \
                bash -c 'printf "compile-start\n"; sleep 2; printf "compile-done\n"'
    )" || return $?
    runner_self_test_assert "grep -q '\[LIVE\].*PHASE=compile elapsed=.*TEST=live_fixture log_size=' <<< \"\$live_output\"" \
        "rich compile live status" || return $?
    runner_self_test_assert "! grep -q ' log=' <<< \"\$live_output\"" \
        "live status does not expose a long log path" || return $?
    parent_output="$(
        export COLUMNS=240
        runner_parent_live_status line seeds "$(( $(date +%s) - 6 ))" 1 4 2 1 'SEED=2'
    )"
    runner_self_test_assert "grep -q '\[HEARTBEAT\].*PHASE=parallel elapsed=.*SCOPE=seeds.*done=1/4.*active=2.*queued=1.*oldest=SEED=2' <<< \"\$parent_output\"" \
        "parallel parent heartbeat" || return $?
    parent_output="$(
        export RUNNER_HEARTBEAT_SEC=2 RUNNER_LIVE_MODE=line
        sleep 1 &
        runner_wait_pid_with_parent_progress "$!" line seeds "$(date +%s)" 0 1 1 0
    )"
    runner_self_test_assert "[[ -z \"\$parent_output\" ]]" \
        "parent heartbeat waits for the configured interval before first output" || return $?
    local slow_worker_pid fast_worker_pid wait_any_rc=0
    local -a wait_any_pids wait_any_indexes
    REG_PLAN_BURST=(B001 B002)
    REG_RUN_DIR="$(runner_out_dir)/self-test/wait-any"
    REG_HEARTBEAT_SEC=0
    sleep 2 & slow_worker_pid=$!
    sleep 1 & fast_worker_pid=$!
    wait_any_pids=("$slow_worker_pid" "$fast_worker_pid")
    wait_any_indexes=(0 1)
    runner_regression_wait_any wait_any_pids wait_any_indexes quiet bursts \
        "$(date +%s)" 0 2 0 || wait_any_rc=$?
    runner_self_test_assert \
        "[[ '$REG_COMPLETED_SLOT' == 1 && '$REG_COMPLETED_PID' == '$fast_worker_pid' && '$wait_any_rc' == 0 ]]" \
        "parallel regression reaps the first completed worker" || return $?
    wait "$slow_worker_pid" || return $?
    REG_HEARTBEAT_SEC=1
    parent_activity_root="$(runner_out_dir)/self-test/heartbeat/B001/attempt_001"
    mkdir -p "$parent_activity_root/compile_logs"
    printf 'compile activity\n' > "$parent_activity_root/compile_logs/compile.log"
    parent_output="$(runner_parent_live_status line bursts "$(date +%s)" 0 1 1 0 'BURST=B001' "${parent_activity_root%/attempt_001}")"
    runner_self_test_assert "grep -q 'PHASE=compile.*log_size=' <<< \"\$parent_output\"" \
        "parent heartbeat reports compile activity" || return $?
    mkdir -p "$parent_activity_root/metadata"
    : > "$parent_activity_root/metadata/compile.meta"
    mkdir -p "$parent_activity_root/tests/basic_test/seed_1/attempt_001/logs"
    printf 'run activity\n' > "$parent_activity_root/tests/basic_test/seed_1/attempt_001/logs/sim.log"
    parent_output="$(runner_parent_live_status line bursts "$(date +%s)" 0 1 1 0 'BURST=B001' "${parent_activity_root%/attempt_001}")"
    runner_self_test_assert "grep -q 'PHASE=run.*log_size=' <<< \"\$parent_output\"" \
        "parent heartbeat reports run activity" || return $?
    local worker_case_status="$self_test_root/worker-case-status.tsv"
    local reported_case_status="$self_test_root/reported-case-status.tsv"
    printf 'timestamp|burst_id|burst_attempt|test|seed|seed_attempt|status\nnow|B001|A001|basic_test|1|A001|PASS\n' > "$worker_case_status"
    printf 'timestamp|burst_id|burst_attempt|test|seed|seed_attempt|status\n' > "$reported_case_status"
    RUNNER_PARENT_STATUS_FILE="$reported_case_status" RUNNER_PARENT_STATUS_KIND=regression_case
    parent_output="$(runner_parent_live_status line bursts "$(date +%s)" 0 1 1 0 'BURST=B001')"
    runner_self_test_assert "grep -q 'pass=0 fail=0' <<< \"\$parent_output\"" \
        "worker completion is not counted before its result is printed" || return $?
    printf 'now|B001|A001|basic_test|1|A001|PASS\n' >> "$reported_case_status"
    parent_output="$(runner_parent_live_status line bursts "$(date +%s)" 1 1 0 0 'BURST=B001')"
    runner_self_test_assert "grep -q 'pass=1 fail=0' <<< \"\$parent_output\"" \
        "heartbeat counts a result after parent reporting" || return $?
    unset RUNNER_PARENT_STATUS_FILE RUNNER_PARENT_STATUS_KIND
    local report_state report_output report_pid
    report_state="$(mktemp)" || return 1
    report_output="$(
        export RUNNER_LIVE_MODE=line RUNNER_REPORT_PROGRESS_FILE="$report_state" COLUMNS=240
        runner_report_progress_update artifact-index
        runner_report_elapsed_heartbeat "$(( $(date +%s) - 5 ))" "$(date +%s)" "$report_state" 1 line regression \
            'tests=2 cases=4' &
        report_pid=$!
        sleep 2
        runner_report_stop_elapsed_heartbeat "$report_pid" "$report_state"
    )"
    runner_self_test_assert "grep -q '\[HEARTBEAT\].*PHASE=report elapsed=.*SCOPE=regression report_elapsed=.*step=artifact-index tests=2 cases=4' <<< \"\$report_output\"" \
        "reporting heartbeat exposes elapsed time and current step" || return $?
    runner_self_test_assert "[[ ! -e '$report_state' ]]" "reporting heartbeat removes its state file" || return $?

    export DRY_RUN=1
    export TEST_LIST_FILE="${DV_TESTPLAN_OVERRIDE:-$TEST_LIST_FILE}"
    local token; token="$(runner_timestamp)_$$"
    local compile_id="selftest_compile_$token" single_id="selftest_single_$token" reg_id="selftest_reg_$token" cov_id="selftest_cov_$token" isolation_id="selftest_isolation_$token"

    runner_run_compile --scheduler local --run-id "$compile_id" --show-output || return $?
    runner_self_test_assert "grep -q 'COMPILE_JOBS=4' '$(runner_runs_dir)/$compile_id/metadata/commands/compile.sh'" \
        "compile command records four VCS jobs" || return $?
    runner_self_test_assert "grep -q '^compile_jobs=4$' '$(runner_runs_dir)/$compile_id/metadata/compile.meta'" \
        "compile metadata records the VCS job count" || return $?
    runner_self_test_assert "find '$(runner_runs_dir)' -path '*/summary/compile.log' -type f | grep -q ." "compile summary report" || return $?
    runner_self_test_assert "find '$(runner_runs_dir)' -path '*/metadata/commands/compile.sh' -type f | grep -q ." "replayable compile command" || return $?
    runner_self_test_assert "find '$(runner_runs_dir)' -path '*/compile_logs/compile.clean.log' -type f | grep -q ." "normalized compile log" || return $?
    runner_run_test -t basic_test --seeds 1,2,3,4 --jobs 2 --seed-retry-max 3 \
        --scheduler local --dump-format vcd --id "$single_id" --no-comp --show-output || return $?
    runner_self_test_assert "grep -q '^simulation_cpus=1$' '$(runner_runs_dir)/$single_id/metadata/run.meta'" \
        "simulation seeds remain single-CPU by default" || return $?
    runner_self_test_assert "grep -q '^compile_jobs=4$' '$(runner_runs_dir)/$single_id/metadata/run.meta'" \
        "test metadata keeps the independent compile default" || return $?
    runner_self_test_assert "[[ -f '$(runner_runs_dir)/$single_id/summary/seeds.tsv' ]]" "single-test seed summary" || return $?
    runner_self_test_assert "grep -q 'Passed       : 4' '$(runner_runs_dir)/$single_id/summary/test.log'" "single-test PASS dashboard" || return $?
    runner_self_test_assert "grep -q 'dump_status|dump_file' '$(runner_runs_dir)/$single_id/summary/seeds.tsv'" "dump artifact fields are reported separately" || return $?
    runner_self_test_assert "grep -q '|DRY_RUN|' '$(runner_runs_dir)/$single_id/summary/seeds.tsv'" "dry-run dump request does not change functional verdict" || return $?
    runner_self_test_assert "grep -q 'UVM Warning/Error/Fatal' '$(runner_runs_dir)/$single_id/summary/test.log'" "UVM result counters" || return $?
    runner_self_test_assert "grep -q '^Compile Log  : -$' '$(runner_runs_dir)/$single_id/summary/test.log' && awk '/^UVM W\/E\/F/{metrics=NR} /^Compile Log/{compile=NR} /^Detail Log/{detail=NR} END {exit !(metrics && compile>metrics && detail>compile)}' '$(runner_runs_dir)/$single_id/summary/test.log'" \
        "single-test summary keeps metrics before compile and detail log links" || return $?
    runner_self_test_assert "[[ \$(grep -c '^\[CASE-RESULT ' '$(runner_runs_dir)/$single_id/summary/test.log') -eq 4 ]] && ! grep -q '^\[SEED-RESULT\|^Burst        :\|^.*Attempt *:' '$(runner_runs_dir)/$single_id/summary/test.log'" \
        "single-test summary uses regression case formatting without burst or attempt fields" || return $?
    runner_self_test_assert "grep -q '^Case         : default$' '$(runner_runs_dir)/$single_id/summary/test.log' && grep -q '^Level        : direct$' '$(runner_runs_dir)/$single_id/summary/test.log' && grep -q '^Dump Format  : vcd$' '$(runner_runs_dir)/$single_id/summary/test.log'" \
        "single-test case results preserve direct-run and dump context" || return $?
    runner_self_test_assert "[[ -f '$(runner_runs_dir)/$single_id/summary/run_summary.html' ]] && grep -q '<th>Dump</th><th>Compile</th><th>Detail</th>' '$(runner_runs_dir)/$single_id/summary/run_summary.html' && ! grep -q 'href=\"/' '$(runner_runs_dir)/$single_id/summary/run_summary.html'" \
        "single-test HTML summary uses relative artifact links" || return $?
    runner_self_test_assert "find '$(runner_runs_dir)/$single_id/tests' -name command.sh -type f | grep -q ." "replayable test command" || return $?

    runner_run_test -t basic_test --seeds 7,8 --jobs 2 --scheduler local --cov --id "$isolation_id" --no-comp || return $?
    runner_self_test_assert "[[ -d '$(runner_runs_dir)/$isolation_id/tests/basic_test/seed_7/attempt_001/run_work' ]]" "seed 7 private run directory" || return $?
    runner_self_test_assert "[[ -d '$(runner_runs_dir)/$isolation_id/tests/basic_test/seed_8/attempt_001/run_work' ]]" "seed 8 private run directory" || return $?
    runner_self_test_assert "grep -q 'seed_7/attempt_001/coverage' '$(runner_runs_dir)/$isolation_id/tests/basic_test/seed_7/attempt_001/logs/sim.log'" "seed 7 private coverage path" || return $?
    runner_self_test_assert "grep -q 'seed_8/attempt_001/coverage' '$(runner_runs_dir)/$isolation_id/tests/basic_test/seed_8/attempt_001/logs/sim.log'" "seed 8 private coverage path" || return $?

    local planner_fixture="$self_test_root/planner.dv"
    cat > "$planner_fixture" <<'EOF'
# DV_TESTPLAN_VERSION=1
# test|group|level|enabled|seed_policy|default_seeds|plusargs|tags
# BURST_LIMITS light=2 medium=2 heavy=1 extra=1
# BURST_PLAN light=test-major medium=test-major heavy=test-major extra=test-major
planner_test_a|planner|light|on|all|1,2,3||self-test
planner_test_b|planner|light|on|all|1,2,3||self-test,random-seed
EOF
    REG_EXCLUDED_TESTS_CSV=''; REG_EXCLUDED_GROUPS_CSV=''
    runner_regression_load_plan "$planner_fixture" 0 '' 0 test-major 0 || return $?
    runner_self_test_assert "[[ ${#REG_PLAN_TEST[@]} -eq 4 ]]" "test-major splits seeds by BURST_LIMITS" || return $?
    runner_self_test_assert "[[ '${REG_PLAN_TEST[*]}' == 'planner_test_a planner_test_a planner_test_b planner_test_b' ]]" \
        "test-major completes one test before the next" || return $?
    runner_self_test_assert "[[ '${REG_PLAN_SEEDS[*]}' == '1,2 3 1,2 3' ]]" \
        "test-major preserves seed chunks" || return $?
    runner_regression_load_plan "$planner_fixture" 0 '' 0 auto 0 || return $?
    runner_self_test_assert "[[ ${#REG_PLAN_TEST[@]} -eq 4 && '${REG_PLAN_SEEDS[*]}' == '1,2 3 1,2 3' ]]" \
        "auto case order honors BURST_PLAN metadata" || return $?
    runner_regression_load_plan "$planner_fixture" 0 '' 0 seed-major 0 || return $?
    runner_self_test_assert "[[ ${#REG_PLAN_TEST[@]} -eq 6 ]]" "seed-major creates one test-seed burst" || return $?
    runner_self_test_assert "[[ '${REG_PLAN_TEST[*]}' == 'planner_test_a planner_test_b planner_test_a planner_test_b planner_test_a planner_test_b' ]]" \
        "seed-major completes one seed across tests before advancing" || return $?
    runner_self_test_assert "[[ '${REG_PLAN_SEEDS[*]}' == '1 1 2 2 3 3' ]]" \
        "seed-major preserves seed order" || return $?
    runner_regression_load_plan "$planner_fixture" 0 '' 2 test-major 0 || return $?
    runner_self_test_assert "[[ '${REG_PLAN_TEST[*]}' == 'planner_test_a planner_test_a planner_test_b' && '${REG_PLAN_SEEDS[0]} ${REG_PLAN_SEEDS[1]}' == '1,2 3' ]]" \
        "rand-num preserves directed plan seeds" || return $?
    runner_split_csv "${REG_PLAN_SEEDS[2]}"
    runner_self_test_assert "[[ ${#RUNNER_SPLIT_RESULT[@]} -eq 2 ]]" \
        "rand-num replaces seeds only for random-seed tagged entries" || return $?

    local per_entry_fixture="$self_test_root/per-entry.dv"
    cat > "$per_entry_fixture" <<'EOF'
# DV_TESTPLAN_VERSION=2
# test|case_id|group|level|enabled|seed_policy|default_seeds|plusargs|tags|compile_requirements
# BURST_LIMITS light=20 medium=20 heavy=20 extra=20
# BURST_PLAN light=test-major medium=test-major heavy=test-major extra=test-major
shared_test|accept_case|per_entry|light|on|all|1|+POLICY=accept|self-test|
shared_test|reject_case|per_entry|light|on|all|1|+POLICY=reject|self-test|
EOF
    runner_regression_load_plan "$per_entry_fixture" 0 '' 0 test-major 0 test:shared_test || return $?
    runner_self_test_assert "[[ '${REG_PLAN_CASE_ID[*]}' == 'accept_case reject_case' ]]" \
        "per-entry cases keep independent identities" || return $?
    runner_self_test_assert "[[ '${REG_PLAN_PLUSARGS[*]}' == '+POLICY=accept +POLICY=reject' ]]" \
        "per-entry plusargs reach the burst plan" || return $?
    runner_regression_load_plan "$per_entry_fixture" 0 '' 0 test-major 0 case:reject_case || return $?
    runner_self_test_assert "[[ ${#REG_PLAN_TEST[@]} -eq 1 && '${REG_PLAN_CASE_ID[0]}' == reject_case && '${REG_PLAN_PLUSARGS[0]}' == '+POLICY=reject' ]]" \
        "case selector isolates one per-entry configuration" || return $?

    local policy_fixture="$self_test_root/seed_policy.dv"
    cat > "$policy_fixture" <<'EOF'
# DV_TESTPLAN_VERSION=1
# test|group|level|enabled|seed_policy|default_seeds|plusargs|tags
# BURST_LIMITS light=20 medium=20 heavy=20 extra=20
# BURST_PLAN light=test-major medium=test-major heavy=test-major extra=test-major
policy_test_all|policy|light|on|all|1,2,3||coverage-seed=first,coverage-iteration=once
policy_test_fixed|policy|light|on|fixed:7|1,2,3||self-test
policy_test_cap|policy|light|on|cap:2|1,2,3||self-test
EOF
    runner_regression_load_plan "$policy_fixture" 0 '' 0 test-major 0 || return $?
    runner_self_test_assert "[[ '${REG_PLAN_SEEDS[*]}' == '1,2,3 7 1,2' ]]" \
        "regression seed policies preserve all, fixed, and capped seeds" || return $?
    runner_regression_load_plan "$policy_fixture" 0 '' 0 test-major 1 || return $?
    runner_self_test_assert "[[ '${REG_PLAN_SEEDS[*]}' == '1 7 1,2' ]]" \
        "coverage seed policy overrides regression policy" || return $?
    runner_self_test_assert "[[ \"\$(runner_coverage_once_tests '$policy_fixture')\" == policy_test_all ]]" \
        "coverage closure policy identifies run-once tests" || return $?

    local -a fixture_tests=() regression_selectors=()
    mapfile -t fixture_tests < <(awk -F'|' '/^#[[:space:]]*DV_TESTPLAN_VERSION=2/{v2=1;next} !/^[[:space:]]*#/ && NF && $(v2?5:4) == "on" && $1 ~ /^i3c_ibi_/ {print $1; if (++count == 2) exit}' "$TEST_LIST_FILE")
    ((${#fixture_tests[@]} > 0)) || { runner_error "Self-test needs at least one test-plan entry"; return 1; }
    for token in "${fixture_tests[@]}"; do regression_selectors+=(-t "$token"); done
    local regression_console="$(runner_runs_dir)/$reg_id.compact.console.log" fixture_case_count
    runner_run_regression "${regression_selectors[@]}" --worker 2 --burst-max 2 --burst-start-gap-sec 0 \
        --attempt-retry-max 1 --retry-schedule deferred-wave --scheduler local --id "$reg_id" > "$regression_console" || return $?
    fixture_case_count="$(awk -F'|' 'NR==1{v2=($3=="case_id");next} {count+=split($(v2?5:4),seeds,",")} END {print count+0}' "$(runner_runs_dir)/$reg_id/metadata/manifest.tsv")"
    runner_self_test_assert "grep -q '^\[REGRESSION\]' '$regression_console'" "compact regression header" || return $?
    runner_self_test_assert "grep -q '^\[PLAN\] B[0-9][0-9][0-9] ' '$regression_console'" "compact regression test plan" || return $?
    runner_self_test_assert "[[ \$(grep -c '^\[PLAN\] B[0-9]' '$regression_console') -eq $fixture_case_count ]]" "one compact plan row per test and seed" || return $?
    runner_self_test_assert "! grep '^\[PLAN\] B[0-9]' '$regression_console' | grep -q ' seeds='" "compact plan uses one seed per row" || return $?
    runner_self_test_assert "grep -q '^--------------------------------------------------------------------------------$' '$regression_console'" "plan execution separator" || return $?
    runner_self_test_assert "[[ \$(grep -Ec '^\[PASS\]  B[0-9]{3} A[0-9]{3} [LMHX?] S=.* T=.* C=' '$regression_console') -eq $fixture_case_count ]]" \
        "one compact result per test and seed" || return $?
    runner_self_test_assert "[[ \$(grep -Ec '^\[START\] B[0-9]{3} A[0-9]{3} [LMHX?] S=.* T=.* C=' '$regression_console') -eq $fixture_case_count ]]" \
        "one compact START row per test and seed" || return $?
    runner_self_test_assert "[[ \$(grep -c '^\[HEARTBEAT\] PHASE=complete SCOPE=regression.*tests=${#fixture_tests[@]} cases=$fixture_case_count pass=$fixture_case_count fail=0$' '$regression_console') -eq 1 ]]" "single final regression heartbeat" || return $?
    runner_self_test_assert "awk '/Regression Summary/{summary=NR} /^\[HEARTBEAT\] PHASE=complete/{complete=NR} END {exit !(summary && complete && summary < complete)}' '$regression_console'" \
        "final complete heartbeat follows regression reporting" || return $?
    runner_self_test_assert "! grep -Eq 'state=(phase|worker)-complete' '$regression_console'" "no persistent phase heartbeat checkpoints" || return $?
    runner_self_test_assert "grep -q '^\[PASS\] REGRESSION' '$regression_console'" "compact regression final status" || return $?
    runner_self_test_assert "[[ -f '$(runner_runs_dir)/$reg_id/metadata/manifest.tsv' ]]" "regression manifest" || return $?
    runner_self_test_assert "[[ \$(( \$(wc -l < '$(runner_runs_dir)/$reg_id/metadata/case_status.tsv') - 1 )) -eq $fixture_case_count ]]" "regression case status database" || return $?
    runner_self_test_assert "awk -F'|' 'NR==1 {if (\$5 != \"case_id\" || \$6 != \"level\" || \$7 != \"plusargs\" || \$20 != \"error_total\" || \$21 != \"dump_status\" || \$22 != \"dump_format\" || \$23 != \"dump_file\") exit 1; next} {if (NF != 23 || \$20 !~ /^[0-9]+$/) exit 1}' '$(runner_runs_dir)/$reg_id/metadata/case_status.tsv'" \
        "regression records case metrics and dump provenance in its case database" || return $?
    runner_self_test_assert "find '$(runner_runs_dir)/$reg_id/bursts' -path '*/summary/error_totals.tsv' -type f | grep -q ." \
        "test reporting publishes reusable error-total caches" || return $?
    runner_self_test_assert "[[ \$(find '$(runner_runs_dir)/$reg_id/bursts' -name attempt.result | wc -l) -eq ${#fixture_tests[@]} ]]" "regression burst results" || return $?
    runner_self_test_assert "grep -q 'Passed       : $fixture_case_count' '$(runner_runs_dir)/$reg_id/summary/regression.log'" "case-level regression PASS dashboard" || return $?
    runner_self_test_assert "grep -q '^Case         :' '$(runner_runs_dir)/$reg_id/summary/regression.log' && grep -q '^Plusargs     :' '$(runner_runs_dir)/$reg_id/summary/regression.log'" \
        "human regression summary records full case and plusarg labels" || return $?
    runner_self_test_assert "! grep -q '^Compile Results:$\|^\[COMPILE-RESULT' '$(runner_runs_dir)/$reg_id/summary/regression.log'" \
        "regression summary keeps compile data inside each case result" || return $?
    runner_self_test_assert "grep -q '^Compile Log  : .*compile_logs/compile.log$' '$(runner_runs_dir)/$reg_id/summary/regression.log' && awk '/^UVM W\/E\/F/{metrics=NR} /^Compile Log/{compile=NR} /^Detail Log/{detail=NR} END {exit !(metrics && compile>metrics && detail>compile)}' '$(runner_runs_dir)/$reg_id/summary/regression.log'" \
        "regression case results end with real compile and detail log links" || return $?
    runner_self_test_assert "grep -q '^Dump Status  :' '$(runner_runs_dir)/$reg_id/summary/regression.log' && grep -q '^Dump Format  :' '$(runner_runs_dir)/$reg_id/summary/regression.log' && grep -q '^Dump File    :' '$(runner_runs_dir)/$reg_id/summary/regression.log'" \
        "regression case results expose dump status, format, and file" || return $?
    runner_self_test_assert "[[ -f '$(runner_runs_dir)/$reg_id/summary/run_summary.html' ]] && grep -q 'data-status=\"PASS\"' '$(runner_runs_dir)/$reg_id/summary/run_summary.html'" \
        "regression publishes a case-aware HTML summary" || return $?
    local coverage_summary_fixture="$self_test_root/coverage-summary-schema"
    mkdir -p "$coverage_summary_fixture/iterations/I001/summary" \
        "$coverage_summary_fixture/iterations/I001/metadata" \
        "$coverage_summary_fixture/iterations/I001/bursts/B001/attempt_001/summary" \
        "$coverage_summary_fixture/iterations/I001/bursts/B001/attempt_001/compile_logs" \
        "$coverage_summary_fixture/iterations/I001/bursts/B001/attempt_001/metadata"
    cat > "$coverage_summary_fixture/iterations/I001/summary/regression.cases.latest.tsv" <<'EOF'
2026-01-01T00:00:00+00:00|B001|A001|coverage_pass_test|pass_case|medium|+MODE=pass|1|A001|PASS|0|PASS|257|/tmp/pass.log|4|0|0|0|0|0|CREATED|fsdb|/tmp/pass.fsdb
2026-01-01T00:00:01+00:00|B002|A001|coverage_fail_test|fail_case|heavy|+MODE=fail|2|A002|FAIL|1|UVM_FAIL|17|/tmp/fail.log|3|1|1|2|1|4|MISSING|vcd|/tmp/fail.vcd
EOF
    local coverage_compile_attempt="$coverage_summary_fixture/iterations/I001/bursts/B001/attempt_001"
    printf 'B001|coverage_pass_test|1|A001|PASS|0|PASS|%s\n' "$coverage_compile_attempt" \
        > "$coverage_summary_fixture/iterations/I001/summary/regression.latest.tsv"
    printf 'Status       : PASS\nReturn Code  : 0\nDuration     : 0d 00h 00m 03s\nError Class  : NONE\n' \
        > "$coverage_compile_attempt/summary/compile.log"
    : > "$coverage_compile_attempt/compile_logs/compile.log"
    : > "$coverage_compile_attempt/compile_logs/compile.clean.log"
    printf 'scheduler=local\ncompile_jobs=4\ncoverage=1\ndump_format=fsdb\ncommand_file=%s\nstatus=0\n' \
        "$coverage_compile_attempt/metadata/commands/compile.sh" > "$coverage_compile_attempt/metadata/compile.meta"
    : > "$coverage_summary_fixture/iterations/I001/metadata/manifest.tsv"
    runner_coverage_publish_regression_summaries "$coverage_summary_fixture" || return $?
    local coverage_schema_log="$coverage_summary_fixture/summary/regression.log"
    local coverage_schema_failures="$coverage_summary_fixture/summary/failures.log"
    runner_self_test_assert "grep -q '^Passed         : 1$' '$coverage_schema_log' && grep -q '^Failed         : 1$' '$coverage_schema_log'" \
        "coverage summary counts PASS and FAIL from the v2 case schema" || return $?
    runner_self_test_assert "grep -q '^Case          : pass_case$' '$coverage_schema_log' && grep -q '^Level         : medium$' '$coverage_schema_log' && grep -q '^Plusargs      : +MODE=pass$' '$coverage_schema_log'" \
        "coverage summary preserves case metadata" || return $?
    runner_self_test_assert "grep -q '^Time          : 0d 00h 04m 17s$' '$coverage_schema_log' && grep -q '^Detail Log    : /tmp/pass.log$' '$coverage_schema_log'" \
        "coverage summary preserves duration and log fields" || return $?
    runner_self_test_assert "grep -q '^UVM W/E/F     : 4/0/0$' '$coverage_schema_log' && grep -q '^SVA Error     : 0$' '$coverage_schema_log'" \
        "coverage summary preserves UVM and SVA metrics" || return $?
    runner_self_test_assert "grep -q '^Dump Status   : CREATED$' '$coverage_schema_log' && grep -q '^Dump Format   : fsdb$' '$coverage_schema_log' && grep -q '^Dump File     : /tmp/pass.fsdb$' '$coverage_schema_log'" \
        "coverage summary preserves dump status, format, and file" || return $?
    runner_self_test_assert "[[ -f '$coverage_summary_fixture/summary/run_summary.html' ]] && grep -q '>I001<' '$coverage_summary_fixture/summary/run_summary.html' && ! grep -q 'href=\"/' '$coverage_summary_fixture/summary/run_summary.html'" \
        "coverage publishes one HTML summary with relative iteration links" || return $?
    runner_self_test_assert "! grep -q '^Compile Results:$\|^\[COMPILE-RESULT' '$coverage_schema_log' && grep -q '^Compile Log   : .*compile_logs/compile.log$' '$coverage_schema_log'" \
        "coverage summary keeps the real compile log inside each case result" || return $?
    runner_self_test_assert "awk '/^UVM W\/E\/F/{metrics=NR} /^Compile Log/{compile=NR} /^Detail Log/{detail=NR} END {exit !(metrics && compile>metrics && detail>compile)}' '$coverage_schema_log'" \
        "coverage case results place compile and detail logs after runtime metrics" || return $?
    runner_self_test_assert "grep -q '^Case      : fail_case$' '$coverage_schema_failures' && grep -q '^Plusargs  : +MODE=fail$' '$coverage_schema_failures' && grep -q '^Reason    : UVM_FAIL$' '$coverage_schema_failures'" \
        "coverage failure summary uses the result and metadata fields" || return $?
    printf 'invalid|schema\n' > "$coverage_summary_fixture/invalid.cases.tsv"
    runner_self_test_assert "! runner_coverage_validate_case_schema '$coverage_summary_fixture/invalid.cases.tsv' >/dev/null 2>&1" \
        "coverage summary rejects an incompatible case schema" || return $?
    runner_self_test_assert "grep -q 'compile_policy=independent_per_burst' '$(runner_runs_dir)/$reg_id/metadata/run.meta'" "private compile per burst policy" || return $?
    runner_self_test_assert "find '$(runner_runs_dir)/$reg_id/bursts' -name console.log -type f | grep -q ." "private burst console logs" || return $?

    export COVERAGE_VALUE_CMD='echo 100'
    runner_self_test_assert "[[ \"${COVERAGE_VALUE_CMD:-}\" == 'echo 100' ]]" "coverage value command export" || return $?
    DV_REQUIRED_COVERAGE_METRICS='' runner_run_coverage -t basic_test --seed 9 --scheduler local \
        --id "$cov_id" --target 95 --max-seeds 2 --show-output || return $?
    unset COVERAGE_VALUE_CMD
    runner_self_test_assert "[[ -f '$(runner_out_dir)/coverage/$cov_id/logs/merge.log' ]]" "coverage merge log" || return $?
    runner_self_test_assert "grep -q 'Value        : 100' '$(runner_out_dir)/coverage/$cov_id/coverage.log'" "coverage dashboard metric" || return $?

    local fixture="$(runner_runs_dir)/$single_id"
    mkdir -p "$fixture/build/csrc" "$fixture/build/simv.daidir" "$fixture/dumps/.wave_cache" "$fixture/logs/basic_test/seed_1"
    : > "$fixture/dumps/basic_test_seed_1.vcd"
    : > "$fixture/dumps/.wave_cache/cache.fsdb"
    : > "$fixture/logs/basic_test/seed_1/attempt_001.log"
    local mapped_attempt mapped_wave mapped_log unrelated_log wave_listing
    mapped_attempt="$fixture/tests/basic_test/seed_1/attempt_001"
    mapped_wave="$mapped_attempt/dumps/basic_test_seed_1_attempt_1.vcd"
    mapped_log="$mapped_attempt/logs/sim.clean.log"
    unrelated_log="$(runner_runs_dir)/newer_unrelated_run/tests/basic_test/seed_1/attempt_001/logs/sim.clean.log"
    mkdir -p "$(dirname "$mapped_wave")" "$(dirname "$mapped_log")" \
             "$(dirname "$unrelated_log")"
    : > "$mapped_wave"
    printf 'mapped log\n' > "$mapped_log"
    printf 'wrong newer log\n' > "$unrelated_log"
    local source_filelist="$fixture/source.f"
    : > "$source_filelist"
    {
        printf 'top=tb_top\n'
        printf 'filelist=%s\n' "$source_filelist"
        printf 'compile_work_dir=%s\n' "$fixture"
        printf 'build_dir=%s\n' "$fixture/build"
        printf 'debug_db=%s\n' "$fixture/build/simv.daidir"
        printf 'verdi_kdb=1\n'
    } > "$fixture/compile.meta"
    runner_wave_prepare_verdi_source_context "$mapped_wave" auto || return $?
    runner_self_test_assert "[[ \"\$RUNNER_WAVE_SOURCE_ACTUAL\" == debug-db ]]" \
        "auto wave source mapping prefers the matching KDB" || return $?
    runner_self_test_assert "[[ \"\${RUNNER_WAVE_SOURCE_ARGS[*]}\" == *'-dbdir $fixture/build/simv.daidir'* ]]" \
        "KDB source mapping uses the recorded debug database" || return $?
    rm -rf "$fixture/build/simv.daidir"
    runner_wave_prepare_verdi_source_context "$mapped_wave" auto || return $?
    runner_self_test_assert "[[ \"\$RUNNER_WAVE_SOURCE_ACTUAL\" == reparse ]]" \
        "auto wave source mapping falls back to filelist reparse" || return $?
    runner_self_test_assert "[[ \"\${RUNNER_WAVE_SOURCE_ARGS[*]}\" == *'-f $source_filelist -top tb_top'* ]]" \
        "reparse source mapping uses the recorded filelist and top" || return $?
    runner_wave_prepare_verdi_source_context "$mapped_wave" off || return $?
    runner_self_test_assert "[[ \"\$RUNNER_WAVE_SOURCE_ACTUAL\" == off && \${#RUNNER_WAVE_SOURCE_ARGS[@]} -eq 0 ]]" \
        "off wave source mapping preserves waveform-only viewing" || return $?
    local conversion_fixture mock_converter conversion_input conversion_fsdb conversion_work conversion_invocation
    conversion_fixture="$self_test_root/vcd-conversion"
    mock_converter="$conversion_fixture/mock-vcd2fsdb"
    conversion_input="$conversion_fixture/input.vcd"
    conversion_fsdb="$conversion_fixture/cache/input.vcd.fsdb"
    conversion_work="$conversion_fixture/cache/input.vcd.convert"
    conversion_invocation="$conversion_fixture/invocation"
    mkdir -p "$(dirname "$conversion_fsdb")" "$conversion_invocation"
    : > "$conversion_input"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'out=' \
        'while (($#)); do' \
        '    case "$1" in' \
        '        -o) out="$2"; shift 2 ;;' \
        '        *) shift ;;' \
        '    esac' \
        'done' \
        '[[ -n "$out" ]] || exit 2' \
        'mkdir -p vcd2fsdbLog' \
        'printf "vendor log\n" > vcd2fsdbLog/run.log' \
        'printf "fsdb\n" > "$out"' \
        'printf "mock converter output\n"' > "$mock_converter"
    chmod +x "$mock_converter"
    (
        cd "$conversion_invocation" || exit 1
        VCD2FSDB="$mock_converter" VFAST="$conversion_fixture/missing-vfast" \
            runner_try_vcd_to_fsdb "$conversion_input" "$conversion_fsdb" "$conversion_work"
    ) || return $?
    runner_self_test_assert "[[ -f '$conversion_fsdb' ]]" \
        "VCD conversion creates the FSDB cache" || return $?
    runner_self_test_assert "[[ -f '$conversion_work/vcd2fsdbLog/run.log' ]]" \
        "converter vendor logs stay under the wave cache" || return $?
    runner_self_test_assert "grep -q 'mock converter output' '$conversion_work/conversion.log'" \
        "converter stdout and stderr are retained" || return $?
    runner_self_test_assert "[[ ! -e '$conversion_invocation/vcd2fsdbLog' ]]" \
        "VCD conversion does not leak vendor logs into the caller directory" || return $?
    wave_listing="$(runner_wave_list vcd 10)"
    runner_self_test_assert "grep -Fq '[1] VCD' <<< \"\$wave_listing\" || grep -Fq '[2] VCD' <<< \"\$wave_listing\"" \
        "wave list uses indexed uppercase format" || return $?
    runner_self_test_assert "grep -Fq 'basic_test  seed=1  A001' <<< \"\$wave_listing\"" \
        "wave list reports test seed and attempt" || return $?
    runner_self_test_assert "grep -Fq 'run : $single_id' <<< \"\$wave_listing\"" \
        "wave list reports owning run" || return $?
    runner_self_test_assert "grep -Fq 'log : $(runner_wave_display_path "$mapped_log")' <<< \"\$wave_listing\"" \
        "wave maps to the log in its own attempt" || return $?
    runner_self_test_assert "! grep -Fq '$unrelated_log' <<< \"\$wave_listing\"" \
        "wave never maps to a newer log from another run" || return $?
    runner_self_test_assert "grep -Fq -- '-------------------------------------------------------------------------' <<< \"\$wave_listing\"" \
        "wave entries include a separator" || return $?
    printf 'UVM_ERROR : 1\n' > "$fixture/logs/classify_test_fail.log"
    runner_self_test_assert "[[ \"\$(runner_failure_reason 1 '$fixture/logs/classify_test_fail.log')\" == UVM_FAIL ]]" "functional result classification" || return $?
    runner_self_test_assert "runner_log_has_functional_failure '$fixture/logs/classify_test_fail.log' 0" "UVM errors override a zero simulator return code" || return $?
    local fail_stdout="$fixture/logs/fail_status.stdout" fail_stderr="$fixture/logs/fail_status.stderr"
    runner_report_case_result FAIL B999 A001 output_contract_test 1 1 UVM_FAIL \
        "$fixture/logs/classify_test_fail.log" > "$fail_stdout" 2> "$fail_stderr"
    runner_self_test_assert "grep -q '^\[FAIL\]  B999 A001 - S=1[[:space:]]*T=output_contract_test[[:space:]]*C=-$' '$fail_stdout'" \
        "FAIL verdict is retained by stdout-only logs" || return $?
    runner_self_test_assert "grep -q '^       reasons=' '$fail_stdout' && grep -q '^       log=' '$fail_stdout'" \
        "FAIL causes and log path stay with the stdout verdict" || return $?
    runner_self_test_assert "[[ ! -s '$fail_stderr' ]]" \
        "FAIL status output does not depend on stderr" || return $?
    printf 'Error: SVA: ap_self_test\n' > "$fixture/logs/classify_sva_fail.log"
    runner_self_test_assert "[[ \"\$(runner_failure_reason 0 '$fixture/logs/classify_sva_fail.log')\" == ASSERT_FAIL ]]" "SVA marker classification" || return $?
    runner_self_test_assert "runner_log_has_functional_failure '$fixture/logs/classify_sva_fail.log' 0" "SVA marker overrides a zero simulator return code" || return $?
    runner_self_test_assert "runner_log_has_assertion_failure '$fixture/logs/classify_sva_fail.log'" "SVA marker detection" || return $?
    runner_self_test_assert "[[ \"\$(runner_log_metric_count '$fixture/logs/classify_sva_fail.log' SVA_ERROR)\" == 1 ]]" "plain dollar-error SVA count" || return $?
    runner_self_test_assert "[[ \"\$(runner_log_metric_count '$fixture/logs/classify_sva_fail.log' ERROR_TOTAL)\" == 1 ]]" "SVA dollar-error contributes one total error" || return $?
    printf 'top.u_sva.ap_self_test: started at 10ns failed at 11ns\n' >> "$fixture/logs/classify_sva_fail.log"
    runner_self_test_assert "[[ \"\$(runner_report_assertion_failures '$fixture/logs/classify_sva_fail.log' | wc -l)\" == 1 ]]" \
        "explicit SVA marker suppresses duplicate native assertion diagnostics" || return $?
    printf 'top.u_sva.ap_legacy: started at 100ns failed at 110ns\n' > "$fixture/logs/classify_sva_native_fail.log"
    runner_self_test_assert "[[ \"\$(runner_failure_reason 0 '$fixture/logs/classify_sva_native_fail.log')\" == ASSERT_FAIL ]]" "native VCS assertion fallback classification" || return $?
    printf 'UVM_ERROR @ 12ns: reporter [SVA: ap_uvm_self_test] assertion failed\n' > "$fixture/logs/classify_sva_uvm_fail.log"
    runner_self_test_assert "[[ \"\$(runner_failure_reason 0 '$fixture/logs/classify_sva_uvm_fail.log')\" == ASSERT_FAIL ]]" "UVM SVA marker classification" || return $?
    runner_self_test_assert "[[ \"\$(runner_log_metric_count '$fixture/logs/classify_sva_uvm_fail.log' SVA_ERROR)\" == 1 ]]" "UVM SVA marker count" || return $?
    printf 'UVM_WARNING @ 12ns: reporter [SVA_WAIVED] SVA: ap_waived [WAIVED]\nUVM_ERROR : 0\nUVM_FATAL : 0\n' > "$fixture/logs/classify_sva_waived.log"
    runner_self_test_assert "! runner_log_has_assertion_failure '$fixture/logs/classify_sva_waived.log'" "waived SVA warning is not an assertion failure" || return $?
    runner_self_test_assert "! runner_log_has_functional_failure '$fixture/logs/classify_sva_waived.log' 0" "waived SVA warning keeps a passing functional verdict" || return $?
    runner_self_test_assert "[[ \"\$(runner_log_metric_count '$fixture/logs/classify_sva_waived.log' SVA_ERROR)\" == 0 ]]" "waived SVA warning is excluded from SVA error count" || return $?
    mkdir -p "$fixture/live-phase/attempt_001/tests/example_test"
    runner_self_test_assert "[[ \"\$(runner_parent_activity_snapshot '$fixture/live-phase')\" == run\|0B ]]" "run artifacts supersede missing compile metadata in heartbeat phase" || return $?
    printf 'Error: plain SystemVerilog failure\n' > "$fixture/logs/classify_plain_error.log"
    runner_self_test_assert "[[ \"\$(runner_failure_reason 0 '$fixture/logs/classify_plain_error.log')\" == ERROR_FAIL ]]" "plain dollar-error classification" || return $?
    runner_self_test_assert "runner_log_has_functional_failure '$fixture/logs/classify_plain_error.log' 0" "plain dollar-error overrides a zero simulator return code" || return $?
    printf '\033[31mError: colored SystemVerilog failure\033[0m\n' > "$fixture/logs/classify_colored_error.log"
    runner_strip_ansi_log "$fixture/logs/classify_colored_error.log"
    runner_self_test_assert "[[ \"\$(runner_failure_reason 0 '$fixture/logs/classify_colored_error.log')\" == ERROR_FAIL ]]" "normalized log preserves colored dollar-error classification" || return $?
    printf 'Error: plain failure\nUVM_ERROR : 2\nUVM_FATAL : 1\n' > "$fixture/logs/classify_error_total.log"
    runner_self_test_assert "[[ \"\$(runner_log_metric_count '$fixture/logs/classify_error_total.log' ERROR_TOTAL)\" == 4 ]]" "plain and UVM errors are combined without counting report lines twice" || return $?
    printf 'UVM_ERROR @ 10ns: reporter [ID] failure before summary\n' > "$fixture/logs/classify_uvm_event.log"
    runner_self_test_assert "[[ \"\$(runner_log_metric_count '$fixture/logs/classify_uvm_event.log' ERROR_TOTAL)\" == 1 ]]" "UVM event fallback works without a report summary" || return $?
    printf 'INFO example_scoreboard.sv SCOREBOARD : Mismatches : 0\n' > "$fixture/logs/classify_scoreboard_pass.log"
    runner_self_test_assert "! runner_log_has_functional_failure '$fixture/logs/classify_scoreboard_pass.log' 0" "zero scoreboard mismatches remain PASS" || return $?
    printf 'INFO example_scoreboard.sv SCOREBOARD : Mismatches = 2\n' > "$fixture/logs/classify_scoreboard_fail.log"
    runner_self_test_assert "runner_log_has_functional_failure '$fixture/logs/classify_scoreboard_fail.log' 0" "nonzero scoreboard mismatches remain FAIL" || return $?
    printf 'ERROR example_scoreboard.sv SCOREBOARD_MISMATCH : data mismatch\n' > "$fixture/logs/classify_scoreboard_id.log"
    runner_self_test_assert "runner_log_has_functional_failure '$fixture/logs/classify_scoreboard_id.log' 0" "scoreboard report IDs remain FAIL" || return $?
    printf 'Fatal License Error\n' > "$fixture/logs/classify_infra_fail.log"
    runner_self_test_assert "[[ \"\$(runner_failure_reason 1 '$fixture/logs/classify_infra_fail.log')\" == LICENSE_FAIL ]]" "license result classification" || return $?
    printf 'srun: error: Unable to allocate resources: Socket timed out on send/recv operation\n' > "$fixture/logs/classify_scheduler_fail.log"
    runner_self_test_assert "[[ \"\$(runner_failure_reason 1 '$fixture/logs/classify_scheduler_fail.log')\" == SCHEDULER_FAIL ]]" "Slurm allocation timeout classification" || return $?
    printf '[ARTIFACT] DUMP=MISSING requested_format=fsdb expected_file=missing.fsdb\n' > "$fixture/logs/classify_dump_missing.log"
    runner_self_test_assert "[[ \"\$(runner_failure_reason 0 '$fixture/logs/classify_dump_missing.log')\" == PASS ]]" "missing dump does not rewrite functional verdict" || return $?
    runner_self_test_assert "! runner_log_has_functional_failure '$fixture/logs/classify_dump_missing.log' 0" "missing dump is not a functional failure" || return $?
    local failure_fixture="$(runner_runs_dir)/selftest_reporting_failure"
    mkdir -p "$failure_fixture/summary" "$failure_fixture/logs"
    printf 'UVM_ERROR @ 10ns: reporter [SVA: ap_summary] assertion failed\nUVM_ERROR : 1\n' > "$failure_fixture/logs/failing.log"
    {
        printf 'seed|attempt|status|rc|reason|duration_sec|log|uvm_warning|uvm_error|uvm_fatal|sva_error|scoreboard_failed|dump_status|dump_file\n'
        printf '99|A001|FAIL|1|ASSERT_FAIL|2|%s|0|1|0|1|0|DISABLED|\n' "$failure_fixture/logs/failing.log"
    } > "$failure_fixture/summary/seeds.tsv"
    RUNNER_REPORT_QUIET=1 runner_report_test selftest_reporting_failure failing_test "$failure_fixture" \
        "$failure_fixture/summary/seeds.tsv" "$(( $(date +%s) - 2 ))" 0
    runner_self_test_assert "grep -q 'Failed       : 1' '$failure_fixture/summary/test.log'" "single-test FAIL dashboard" || return $?
    runner_self_test_assert "grep -q 'SVA Error    : 1' '$failure_fixture/summary/test.log'" "single-test SVA error summary" || return $?
    runner_self_test_assert "grep -q 'Error Total  : 1' '$failure_fixture/summary/test.log'" "single-test combined error total" || return $?
    runner_self_test_assert "! grep -qi 'Scoreboard' '$failure_fixture/summary/test.log'" "single-test omits scoreboard counters" || return $?
    runner_self_test_assert "grep -q 'SVA: ap_summary' '$failure_fixture/summary/test.errors.log'" "SVA failure error extract" || return $?
    runner_self_test_assert "grep -q '^  Reason   : RUN:UVM_ERROR=1, ASSERT=1$' '$failure_fixture/summary/failure_quick_links.log'" \
        "single-test quick link classifies UVM and assertion failures" || return $?
    runner_self_test_assert "grep -Fq '  Log      : $failure_fixture/logs/failing.log' '$failure_fixture/summary/failure_quick_links.log'" \
        "single-test quick link points to the failing log" || return $?
    mkdir -p "$fixture/assertion-coverage/report"
    mkdir -p "$fixture/assertion-coverage/runtime/case/logs"
    printf 'Error: SVA: ap_cov_plain\nUVM_ERROR @ 20ns: reporter [SVA: ap_cov_uvm] assertion failed\n' \
        > "$fixture/assertion-coverage/runtime/case/logs/sim.clean.log"
    RUNNER_REPORT_QUIET=1 runner_report_coverage "$fixture/assertion-coverage" FAIL score not-available 0 \
        "$fixture/assertion-coverage/runtime"
    runner_self_test_assert "grep -q 'SVA Error    : 2' '$fixture/assertion-coverage/coverage.log'" \
        "coverage summary reports runtime SVA errors" || return $?
    runner_self_test_assert "! grep -qi 'Scoreboard' '$fixture/assertion-coverage/coverage.log'" \
        "coverage summary omits scoreboard counters" || return $?
    mkdir -p "$fixture/signoff-regression"
    printf 'SVA Error    : 3\nError Total  : 3\n' > "$fixture/signoff-regression/regression.log"
    RUNNER_REPORT_QUIET=1 runner_report_signoff selftest_signoff "$fixture/signoff" FAIL PASS FAIL \
        "$fixture/assertion-coverage/coverage.log" "$fixture/signoff-regression/regression.log"
    runner_self_test_assert "grep -q 'SVA Error    : 5' '$fixture/signoff/summary/signoff.log'" \
        "signoff combines coverage and regression SVA errors" || return $?
    runner_self_test_assert "! grep -qi 'Scoreboard' '$fixture/signoff/summary/signoff.log'" \
        "signoff summary omits scoreboard counters" || return $?
    local cov_view_run=coverage_view_selftest cov_view_root cov_view_selected cov_view_list
    local fake_bin="$fixture/fake-bin" slurm_capture="$fixture/slurm-coverage-view.txt" cov_view_work
    cov_view_root="$(runner_out_dir)/coverage/$cov_view_run"
    mkdir -p "$cov_view_root/raw/merged.vdb" "$cov_view_root/merged.vdb" "$fake_bin"
    printf 'state=APPLIED\n' > "$cov_view_root/waiver.meta"
    cov_view_selected="$(runner_cov_find_database "$cov_view_run" auto '')" || return $?
    runner_self_test_assert "[[ \"\$cov_view_selected\" == '$cov_view_root/merged.vdb' ]]" \
        "coverage view auto-selects the adjusted database" || return $?
    cov_view_selected="$(runner_cov_find_database "$cov_view_run" raw '')" || return $?
    runner_self_test_assert "[[ \"\$cov_view_selected\" == '$cov_view_root/raw/merged.vdb' ]]" \
        "coverage view can select the retained raw database" || return $?
    cov_view_list="$(runner_cov_list_databases 10 "$cov_view_run" auto)" || return $?
    runner_self_test_assert "grep -q 'variant=adjusted' <<< \"\$cov_view_list\" && grep -q 'variant=raw' <<< \"\$cov_view_list\"" \
        "coverage view lists raw and adjusted databases" || return $?
    cat > "$fake_bin/srun" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$slurm_capture"
pwd > "$slurm_capture.cwd"
EOF
    chmod +x "$fake_bin/srun"
    PATH="$fake_bin:$PATH" runner_cov_open_database "$cov_view_root/merged.vdb" verdi 1 '' "$cov_view_run" || return $?
    wait
    runner_self_test_assert "grep -q -- '--export ALL' '$slurm_capture' && grep -q -- '--x11' '$slurm_capture'" \
        "coverage viewer is dispatched through Slurm with X11 and exported environment" || return $?
    runner_self_test_assert "grep -q -- 'verdi -cov -covdir $cov_view_root/merged.vdb' '$slurm_capture'" \
        "coverage viewer receives the selected merged database" || return $?
    cov_view_work="$(runner_cov_view_work_dir "$cov_view_run")"
    runner_self_test_assert "grep -Fxq '$cov_view_work' '$slurm_capture.cwd'" \
        "coverage viewer runs from its managed output workspace" || return $?
    runner_self_test_assert "[[ -r '$cov_view_work/coverage_view.meta' ]]" \
        "coverage viewer records launch metadata under sim/out" || return $?
    runner_clean --view --id "$cov_view_run" || return $?
    runner_self_test_assert "[[ ! -e '$cov_view_work' && -d '$cov_view_root/merged.vdb' ]]" \
        "view cleanup removes only viewer artifacts and preserves merged coverage" || return $?
    runner_open_wave --format any --limit 5 || return $?
    runner_open_wave --help > "$fixture/view_help.txt" || return $?
    runner_self_test_assert "! grep -q 'Command templates:' '$fixture/view_help.txt'" "view help omits command templates" || return $?
    runner_self_test_assert "! grep -q 'Available options:' '$fixture/view_help.txt'" "view help omits the long option catalog" || return $?
    runner_self_test_assert "grep -q '^Examples:' '$fixture/view_help.txt'" "view help keeps quick examples" || return $?
    runner_self_test_assert "grep -q -- '--source-map auto|off|reparse' '$fixture/view_help.txt'" "view help source-map modes" || return $?
    runner_self_test_assert "grep -q -- '--coverage' '$fixture/view_help.txt' && grep -q 'Slurm' '$fixture/view_help.txt'" \
        "view help documents Slurm coverage viewing" || return $?
    runner_print_help > "$fixture/run_help.txt" || return $?
    runner_self_test_assert "grep -q 'quick examples' '$fixture/run_help.txt'" "run help project quick examples" || return $?
    runner_self_test_assert "grep -q '^First run setup:' '$fixture/run_help.txt'" "run help first-run setup" || return $?
    runner_self_test_assert "grep -q './run.sh generate' '$fixture/run_help.txt' && grep -q './run.sh doctor' '$fixture/run_help.txt'" \
        "run help generate and doctor steps" || return $?
    runner_self_test_assert "! grep -q 'Current test list:' '$fixture/run_help.txt'" "run help keeps the test list separate" || return $?
    runner_self_test_assert "grep -q './run.sh list-tests --page 2' '$fixture/run_help.txt' && grep -q './run.sh list-tests --all' '$fixture/run_help.txt'" \
        "run help points to paginated and complete test listings" || return $?
    runner_self_test_assert "! grep -Eq '^\[[0-9]+/[0-9]+\]\[(ON|OFF)\]' '$fixture/run_help.txt'" "run help does not expand project tests" || return $?
    local list_entry_count list_page_size=2 list_page_total
    list_entry_count="$(awk '!/^#/ && NF {n++} END {print n+0}' "$TEST_LIST_FILE")"
    list_page_total=$(( (list_entry_count + list_page_size - 1) / list_page_size ))
    RUNNER_TEST_PAGE_SIZE="$list_page_size" runner_list_tests > "$fixture/list_tests_page1.txt" || return $?
    runner_self_test_assert "grep -q \"Page 1/$list_page_total\" '$fixture/list_tests_page1.txt'" "list-tests reports page and total pages" || return $?
    runner_self_test_assert "[[ \$(grep -Ec '^\\[[0-9]+/[0-9]+\\](\\[ON\\]  |\\[OFF\\] )T=.{60,} \\| C=.{40,} \\| --plusargs \".*\"$' '$fixture/list_tests_page1.txt') -eq $list_page_size ]]" \
        "list-tests uses one shell-safe line per entry and limits the default page" || return $?
    runner_self_test_assert "grep -Eq '\\| C=- +\\| --plusargs \"' '$fixture/list_tests_page1.txt'" \
        "list-tests abbreviates test-name case fallbacks as the default case" || return $?
    runner_list_tests --all --format raw > "$fixture/list_tests_all.raw" || return $?
    runner_self_test_assert "[[ \$(awk '!/^#/ && NF {n++} END {print n+0}' '$fixture/list_tests_all.raw') -eq $list_entry_count ]]" \
        "list-tests raw all preserves every normalized entry" || return $?
    runner_self_test_assert "! runner_list_tests --page 999 --page-size '$list_page_size' >/dev/null 2>&1" \
        "list-tests rejects pages beyond the recalculated total" || return $?
    runner_print_help regression > "$fixture/regression_help.txt" || return $?
    runner_self_test_assert "grep -q -- '--rand-num N' '$fixture/regression_help.txt' && grep -q -- '--worker N; --burst-max N' '$fixture/regression_help.txt'" \
        "regression help exposes random and parallel controls" || return $?

    runner_clean --temp --dry-run --id "$single_id" || return $?
    runner_self_test_assert "[[ -d '$fixture/build' ]]" "dry-run clean preserves build" || return $?
    runner_clean --temp --id "$single_id" || return $?
    runner_self_test_assert "[[ ! -d '$fixture/build' ]]" "temporary clean removes build" || return $?
    runner_self_test_assert "[[ -f '$fixture/dumps/basic_test_seed_1.vcd' ]]" "temporary clean keeps original dump" || return $?
    runner_self_test_assert "[[ -f '$fixture/logs/basic_test/seed_1/attempt_001.log' ]]" "temporary clean keeps logs" || return $?
    runner_self_test_assert "[[ ! -d '$fixture/dumps/.wave_cache' ]]" "temporary clean removes wave cache" || return $?

    runner_clean --dump --id "$single_id" || return $?
    runner_self_test_assert "[[ ! -f '$fixture/dumps/basic_test_seed_1.vcd' ]]" "dump clean removes waveform" || return $?

    local legacy_project="$self_test_root/legacy-project"
    mkdir -p "$legacy_project/sim/out/logs"
    printf 'generated viewer metadata\n' > "$legacy_project/.fsm.sch.verilog.xml"
    (
        export DV_PROJECT_ROOT="$legacy_project" RUNNER_OUT_DIR="$legacy_project/sim/out"
        runner_clean --all
    ) || return $?
    runner_self_test_assert "[[ ! -e '$legacy_project/sim/out' ]]" \
        "clean adopts and removes the legacy project output" || return $?
    runner_self_test_assert "[[ ! -e '$legacy_project/.fsm.sch.verilog.xml' ]]" \
        "clean removes generated FSM metadata outside sim/out" || return $?

    sleep 60 &
    local managed_pid=$!
    RUNNER_ACTIVE_RUN_ID='selftest_managed'; RUNNER_ACTIVE_TEST='managed_test'; RUNNER_ACTIVE_SEED='1'
    runner_register_job "$managed_pid" selftest-managed "$fixture/logs/managed.log"
    local managed_rows
    managed_rows="$(runner_clean_registry_rows selftest_managed '' managed_test 1 "$managed_pid")"
    runner_self_test_assert "[[ -n '$managed_rows' ]]" "active-job filtering" || return $?
    runner_clean kill --pid "$managed_pid" --force || return $?
    wait "$managed_pid" 2>/dev/null || true
    runner_self_test_assert "! kill -0 '$managed_pid' 2>/dev/null" "managed-job termination" || return $?

    local cov_filter_fixture="$(runner_out_dir)/self-test/cov_filter" cov_filter_manifest
    mkdir -p "$cov_filter_fixture/summary" "$cov_filter_fixture/coverage/compile.vdb" \
        "$cov_filter_fixture/tests/pass_test/seed_1/attempt_001/logs" \
        "$cov_filter_fixture/tests/pass_test/seed_1/attempt_001/coverage/pass.vdb" \
        "$cov_filter_fixture/tests/fail_test/seed_2/attempt_001/logs" \
        "$cov_filter_fixture/tests/fail_test/seed_2/attempt_001/coverage/fail.vdb"
    {
        printf '1|A001|PASS|0|PASS|1|%s|0|0|0|0|0\n' "$cov_filter_fixture/tests/pass_test/seed_1/attempt_001/logs/sim.log"
        printf '2|A001|FAIL|1|UVM_FAIL|1|%s|0|1|0|0|0\n' "$cov_filter_fixture/tests/fail_test/seed_2/attempt_001/logs/sim.log"
    } > "$cov_filter_fixture/summary/seeds.latest.tsv"
    printf 'coverage=1\ncompile_vdb=%s\nstatus=0\n' \
        "$cov_filter_fixture/coverage/compile.vdb" > "$cov_filter_fixture/compile.meta"
    cov_filter_manifest="$cov_filter_fixture/vdb_manifest.tsv"
    runner_cov_collect_pass_databases "$cov_filter_fixture" "$cov_filter_manifest"
    runner_self_test_assert "grep -q 'compile.vdb.*DESIGN' '$cov_filter_manifest'" "compile-time design VDB selected" || return $?
    runner_self_test_assert "grep -q 'pass.vdb' '$cov_filter_manifest'" "PASS VDB selected" || return $?
    runner_self_test_assert "! grep -q 'fail.vdb' '$cov_filter_manifest'" "FAIL VDB excluded" || return $?

    local missing_design_fixture="$(runner_out_dir)/self-test/missing_design" missing_design_manifest
    mkdir -p "$missing_design_fixture/summary" \
        "$missing_design_fixture/tests/pass_test/seed_3/attempt_001/logs" \
        "$missing_design_fixture/tests/pass_test/seed_3/attempt_001/coverage/pass.vdb"
    printf '3|A001|PASS|0|PASS|1|%s|0|0|0|0|0\n' \
        "$missing_design_fixture/tests/pass_test/seed_3/attempt_001/logs/sim.log" \
        > "$missing_design_fixture/summary/seeds.latest.tsv"
    printf 'coverage=1\ncompile_vdb=%s\nstatus=0\n' \
        "$missing_design_fixture/coverage/missing_compile.vdb" > "$missing_design_fixture/compile.meta"
    missing_design_manifest="$missing_design_fixture/vdb_manifest.tsv"
    runner_cov_collect_pass_databases "$missing_design_fixture" "$missing_design_manifest"
    runner_self_test_assert "[[ \${#RUNNER_COV_MISSING_DESIGN[@]} -eq 1 ]]" "missing compile-time design VDB detected" || return $?

    local urg_fixture="$(runner_out_dir)/self-test/urg_report" urg_metrics="$cov_filter_fixture/urg_metrics.tsv"
    mkdir -p "$urg_fixture"
    {
        printf 'Total Coverage Summary\n'
        printf 'SCORE LINE COND TOGGLE FSM BRANCH ASSERT GROUP\n'
        printf '91.0 92.0 93.0 94.0 95.0 96.0 97.0 98.0\n'
    } > "$urg_fixture/dashboard.txt"
    runner_coverage_parse_metrics "$urg_fixture" "$urg_metrics" || return $?
    runner_self_test_assert "grep -q '^assert|97.0$' '$urg_metrics' && grep -q '^group|98.0$' '$urg_metrics'" "URG metric matrix parser" || return $?
    {
        printf 'Total Coverage Summary\n'
        printf 'SCORE ASSERT GROUP\n'
        printf '33.26 22.22 44.29\n'
    } > "$urg_fixture/dashboard.txt"
    runner_coverage_parse_metrics "$urg_fixture" "$urg_metrics" || return $?
    runner_self_test_assert "grep -q '^assert|22.22$' '$urg_metrics' && grep -q '^group|44.29$' '$urg_metrics'" "sparse URG columns retain assertion coverage" || return $?
    local metric_rows
    printf 'score|33.26\ngroup|44.29\n' > "$urg_metrics"
    metric_rows="$(runner_coverage_metric_rows "$urg_metrics")"
    runner_self_test_assert "grep -Eq '^ASSERT[[:space:]]+: N/A$' <<< \"\$metric_rows\" && grep -Eq '^GROUP[[:space:]]+: 44.29%$' <<< \"\$metric_rows\"" "coverage summary renders missing metrics as N/A" || return $?
    runner_self_test_assert "! grep -q '^line|' '$urg_metrics' && ! grep -q '^cond|' '$urg_metrics'" "missing URG metrics are not relabeled" || return $?
    {
        printf '<html><body><b>Total Coverage Summary</b><table><tr>'
        printf '<td>SCORE</td><td>LINE</td><td>ASSERT</td><td>GROUP</td></tr><tr>'
        printf '<td>81.0</td><td>82.0</td><td>83.0</td><td>84.0</td></tr></table></body></html>\n'
    } > "$urg_fixture/dashboard.html"
    rm -f "$urg_fixture/dashboard.txt"
    runner_coverage_parse_metrics "$urg_fixture" "$urg_metrics" || return $?
    runner_self_test_assert "grep -q '^line|82.0$' '$urg_metrics' && grep -q '^assert|83.0$' '$urg_metrics' && grep -q '^group|84.0$' '$urg_metrics'" "URG HTML metric parser retains assertion coverage" || return $?
    {
        printf '<html><body><b>Total Coverage Summary</b><table><tr>'
        printf '<td>SCORE</td><td>ASSERT</td><td>GROUP</td></tr><tr>'
        printf '<td>81.0</td><td>N/A</td><td>84.0</td></tr></table></body></html>\n'
    } > "$urg_fixture/dashboard.html"
    runner_coverage_parse_metrics "$urg_fixture" "$urg_metrics" || return $?
    metric_rows="$(runner_coverage_metric_rows "$urg_metrics")"
    runner_self_test_assert "! grep -q '^assert|' '$urg_metrics' && grep -q '^group|84.0$' '$urg_metrics' && grep -Eq '^ASSERT[[:space:]]+: N/A$' <<< \"\$metric_rows\"" "URG HTML missing assertion value preserves later metrics" || return $?
    local cov_validate_fixture="$(runner_out_dir)/self-test/cov_validate"
    mkdir -p "$cov_validate_fixture/report"
    printf 'Total Coverage Summary\nSCORE ASSERT GROUP\n33.26 22.22 44.29\n' > "$cov_validate_fixture/report/dashboard.txt"
    runner_cov_validate_metrics "$cov_validate_fixture" group || return $?
    runner_self_test_assert "! runner_cov_validate_metrics '$cov_validate_fixture' line >/dev/null 2>&1" "required coverage metrics reject missing columns" || return $?

    local waiver_report_fixture="$(runner_out_dir)/self-test/waiver_report"
    mkdir -p "$waiver_report_fixture/raw/report" "$waiver_report_fixture/report"
    printf 'Total Coverage Summary\nSCORE COND BRANCH\n99.83 99.50 99.31\n' \
        > "$waiver_report_fixture/raw/report/dashboard.txt"
    printf 'Total Coverage Summary\nSCORE COND BRANCH\n100.00 100.00 100.00\n' \
        > "$waiver_report_fixture/report/dashboard.txt"
    printf 'EXCLUSION_RULE_FROM_VERDI\n' > "$waiver_report_fixture/filter.el"
    printf 'W4.1|COND|1|rtl/example.sv|condition|reason|evidence|REVIEWED\n' \
        > "$waiver_report_fixture/manifest.tsv"
    runner_cov_write_waiver_report "$waiver_report_fixture" "$waiver_report_fixture/raw" \
        "$waiver_report_fixture/filter.el" "$waiver_report_fixture/manifest.tsv" || return $?
    runner_self_test_assert "grep -Fq '99.83' '$waiver_report_fixture/waivers_applied.txt' && grep -Fq '100.00' '$waiver_report_fixture/waivers_applied.txt'" \
        "waiver report preserves raw and adjusted scores" || return $?
    runner_self_test_assert "grep -q '^W4.1 | COND | cells=1 | REVIEWED$' '$waiver_report_fixture/waivers_applied.txt'" \
        "waiver report records reviewed rule details" || return $?

    local artifact_fixture="$(runner_out_dir)/self-test/artifact_index" artifact_index
    artifact_index="$artifact_fixture/summary/artifacts.tsv"
    mkdir -p "$artifact_fixture/logs" "$artifact_fixture/coverage/sample.vdb/internal/deep" \
        "$artifact_fixture/summary"
    printf 'visible\n' > "$artifact_fixture/logs/run.log"
    printf 'database-internal\n' > "$artifact_fixture/coverage/sample.vdb/internal/deep/object.dat"
    runner_write_artifact_index "$artifact_fixture" "$artifact_index"
    runner_self_test_assert "grep -Fq '$artifact_fixture/logs/run.log' '$artifact_index'" \
        "artifact index retains normal logs" || return $?
    runner_self_test_assert "awk -F'|' '\$1==\"log\" && \$2==\"$artifact_fixture/logs/run.log\" {if (\$3 != 8 || \$4 !~ /^20[0-9][0-9]-/) exit 1; found=1} END {exit !found}' '$artifact_index'" \
        "artifact index records size and timestamp without per-file helpers" || return $?
    runner_self_test_assert "grep -Fq 'coverage_db|$artifact_fixture/coverage/sample.vdb|' '$artifact_index'" \
        "artifact index records each coverage database once" || return $?
    runner_self_test_assert "! grep -Fq 'object.dat' '$artifact_index'" \
        "artifact index prunes coverage database internals" || return $?

    runner_clean --all || return $?
    runner_self_test_assert "[[ ! -e '$(runner_out_dir)' ]]" "full clean removes output root" || return $?
    runner_info "Self-test passed: completion link, live monitoring, PASS/FAIL dashboards, error extracts, parallelism, manifests, coverage, wave discovery, and scoped cleanup"
)
