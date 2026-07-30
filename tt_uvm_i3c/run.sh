#!/usr/bin/env bash

_DV_RUNNER_SOURCED=0
[[ "${BASH_SOURCE[0]}" != "$0" ]] && _DV_RUNNER_SOURCED=1

_dv_runner_source_usage() {
    cat <<'EOF'
Usage when sourced:
  source ./run.sh env

Source mode updates the current shell environment. Execute run.sh
normally for compile, test, regression, coverage, wave, and cleanup commands.
EOF
}

_dv_runner_source_env() {
    local package_root="$1"
    local env_file="$package_root/i3c/sim/vcs_run_script/tt_local_env.sh"
    [[ -r "$env_file" ]] || {
        echo "[ERROR] TT I3C environment file not found: $env_file" >&2
        return 1
    }
    # shellcheck source=/dev/null
    source "$env_file"
}

if ((_DV_RUNNER_SOURCED)); then
    _dv_runner_package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    _dv_runner_status=0
    case "${1:-}" in
        env)
            case "${2:-tt}" in
                tt) _dv_runner_source_env "$_dv_runner_package_root" || _dv_runner_status=$? ;;
                *)
                    echo "[ERROR] Unknown source environment: $2" >&2
                    _dv_runner_status=2
                    ;;
            esac
            ;;
        ''|help|-h|--help) _dv_runner_source_usage ;;
        *)
            echo "[ERROR] source ./run.sh only supports env" >&2
            _dv_runner_source_usage >&2
            _dv_runner_status=2
            ;;
    esac
    unset -f _dv_runner_source_usage _dv_runner_source_env
    unset _DV_RUNNER_SOURCED _dv_runner_package_root
    return "$_dv_runner_status"
fi

set -uo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER_ROOT="$PACKAGE_ROOT/i3c"
RUNNER_SCRIPT_DIR="$RUNNER_ROOT/sim/vcs_run_script"
DV_PROJECT_ROOT="$RUNNER_ROOT"
DV_RUNNER_ENTRYPOINT="$PACKAGE_ROOT/run.sh"
export PACKAGE_ROOT RUNNER_ROOT RUNNER_SCRIPT_DIR
export DV_PROJECT_ROOT DV_RUNNER_ENTRYPOINT

# Load bundled UVM and portable dependency defaults for every public command.
_dv_runner_source_env "$PACKAGE_ROOT" || exit $?
unset -f _dv_runner_source_usage _dv_runner_source_env

# Preserve the qualified simulation working directory while exposing only the
# package-level entry point.
cd "$RUNNER_ROOT"

if [[ "${1:-}" == "--project" ]]; then
    [[ $# -ge 2 ]] || { echo "[ERROR] --project requires a configuration path" >&2; exit 2; }
    export DV_PROJECT_CONFIG="$2"
    shift 2
fi

# shellcheck source=sim/vcs_run_script/project_config.sh
source "$RUNNER_SCRIPT_DIR/project_config.sh"
runner_project_load || exit $?

runner_help_print_tests() {
    local test_file="${TEST_LIST_FILE:-}"
    printf '\nCurrent test list:\n'
    if [[ ! -r "$test_file" ]]; then
        printf '  (unavailable; run ./run.sh generate)\n'
        return 0
    fi
    printf '  %-5s %s\n' STATE TEST
    awk -F'|' '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ {next}
        {
            state=($4 == "on" ? "ON" : "off")
            printf "  [%-3s] %s\n", state, $1
        }
    ' "$test_file"
}

runner_help_summary() {
    local help_title="${DV_HELP_TITLE:-Generic DV Runner}"
    local help_scope="${DV_HELP_SCOPE:-Project}"
    local example_test="${DV_HELP_EXAMPLE_TEST:-smoke_test}"
    local help_tool_setup="${DV_HELP_TOOL_SETUP:-module load vcs verdi}"
    local help_env_components="${DV_HELP_ENV_COMPONENTS:-project dependencies}"
    local help_dep_root_var="${DV_HELP_DEP_ROOT_VAR:-DV_DEPS_ROOT}"
    cat <<EOF
$help_title

Usage:
  ./run.sh <command> [options]
  ./run.sh help <command>

First run setup:
  Load simulator and waveform tools:
    $help_tool_setup

  Select the required dependency checkout, then load the $help_scope
  environment ($help_env_components):
    export $help_dep_root_var=/path/to/tt-i3c-core
    source ./run.sh env

  Select direct local execution without a scheduler:
    export DV_DEFAULT_SCHEDULER=local
    export DV_VIEW_SCHEDULER=local

  Or select Slurm execution:
    export DV_DEFAULT_SCHEDULER=slurm
    export DV_VIEW_SCHEDULER=slurm
    export RUNNER_SLURM_PARTITION=<partition-name>  # only when required

  Generate inputs, validate the environment, compile, and inspect tests:
    ./run.sh generate
    ./run.sh doctor
    ./run.sh comp --show-output
    ./run.sh list-tests

External TT I3C source attachment:
  i3c/sim/project/i3c_inputs.mk:28 adds:
    -f \${I3C_ROOT_DIR}/src/i3c.f
  A manually maintained filelist may replace \${I3C_ROOT_DIR} with the
  absolute path to the TT I3C checkout instead of using an export.

Commands:
  setup        Generate inputs and run environment checks
  smoke        Run CSR smoke and sanity tests
  target       Run all DUT-Target IBI tests serially
  controller   Run all DUT-Controller IBI tests serially
  comp         Compile. Options: --scheduler, --cpus, --cov, --dump-format, --show-output
  test         Single test. Options: -t, --seed/--seeds, --cov, --dump-format, --show-output
  regression   Run all enabled tests serially. Options: --rand-num, --cov
  coverage     Coverage regression/closure. Supports regression options plus --target
  merge-cov    Merge VDBs. Options: --id, --scope, --require-metrics, --show-output
  view         List/open waves and logs. Options: --test, --seed, --last, --open, --format
  summary      Show run summaries. Options: --id, --burst-id, --attempt, --tail
  clean        Scoped cleanup. Options: --temp, --all, --dump, --cov, --log, --id
  generate     Generate project filelists and normalized test plan
  doctor       Validate project and runner configuration
  list-tests   Print the current normalized test list

$help_scope quick examples (using $example_test):
  Compile:
    ./run.sh comp --scheduler slurm

  Run one test and stream simulator output:
    ./run.sh test -t $example_test --show-output

  Run one test with coverage, FSDB, and simulator output:
    ./run.sh test -t $example_test --cov --dump-format fsdb --show-output

  Run every enabled regression entry:
    ./run.sh regression

  Run a full random regression:
    ./run.sh regression --rand-num 10

  Run coverage closure:
    ./run.sh coverage --rand-num 10 --target 90

  Merge latest-PASS coverage databases:
    ./run.sh merge-cov --id <RUN_ID> --show-output

  List and open waveforms:
    ./run.sh view
    ./run.sh view --open --last --fsdb

IBI suite examples:
  ./run.sh target
  ./run.sh controller --cov

More:
  ./run.sh help env|doctor|comp|test|regression|coverage|merge-cov|view
  ./run.sh <command> --help
  ./run.sh help --all
  Read i3c/README.md for execution and artifact contracts.
  Parallel test execution and signoff are intentionally not exposed.
EOF
}

runner_help_command() {
    local topic="$1"
    local example_test="${DV_HELP_EXAMPLE_TEST:-smoke_test}"
    local sanity_test="${DV_HELP_SANITY_TEST:-sanity_test}"
    local help_scope="${DV_HELP_SCOPE:-Project}"
    local help_env_components="${DV_HELP_ENV_COMPONENTS:-project dependencies}"
    local help_dep_root_var="${DV_HELP_DEP_ROOT_VAR:-DV_DEPS_ROOT}"
    case "$topic" in
        env|environment)
            cat <<EOF
$help_scope Environment
  Load $help_env_components settings into the current shell.
  This is a source-only operation; executing ./run.sh env cannot
  update the parent shell.

Usage:
  source ./run.sh env

Select the required source checkout:
  export $help_dep_root_var=/path/to/tt-i3c-core
  source ./run.sh env

Validate the resolved environment:
  ./run.sh doctor
EOF
            ;;
        comp|compile)
            cat <<EOF
Compile
  Build one isolated VCS simulation image. Compile defaults to four VCS jobs.

Usage:
  ./run.sh comp [--scheduler MODE] [--cpus N] [--cov]
                [--dump-format none|vcd|vpd|fsdb] [--show-output]

Examples:
  ./run.sh comp --scheduler slurm
  ./run.sh comp --scheduler slurm --cpus 4 --show-output
  ./run.sh comp --cov --dump-format fsdb --show-output
EOF
            ;;
        test)
            cat <<EOF
Single Test
  Compile once and run one test over one or more seeds.

Options:
  -t, --test NAME; --seed N; --seeds LIST; --rand-num N
  --cov; --dump-format FORMAT; --show-output; --verbosity LEVEL
  --scheduler MODE; --cpus N; --plusargs TEXT; --no-comp

Examples:
  ./run.sh test -t $example_test --show-output
  ./run.sh test -t $sanity_test --seed 1 --show-output
  ./run.sh test -t $example_test --cov --dump-format fsdb --show-output
EOF
            ;;
        regression|regress)
            cat <<EOF
Regression
  Select tests from the normalized test plan and run test/seed cases in bursts.

Options:
  All enabled tests are selected by the handoff runner.
  --seeds LIST; --rand-num N
  --cov; --dump-format FORMAT; --scheduler MODE; --show-output
  --attempt-retry-max N; --seed-retry-max N; --retry-schedule MODE

Examples:
  ./run.sh regression
  ./run.sh regression --rand-num 10
EOF
            ;;
        coverage|cov)
            cat <<EOF
Coverage
  Run a single test or regression with coverage, then merge latest-PASS VDBs.

Options:
  The serial regression options are supported.
  --target PERCENT; --target-metric NAME; --max-seeds N
  --check-interval N; --allow-miss; --skip-merge; --show-output

Examples:
  ./run.sh coverage --rand-num 10
  ./run.sh coverage --target 95 --max-seeds 10
EOF
            ;;
        merge-cov)
            cat <<'EOF'
Coverage Merge
  Merge compile/runtime VDBs selected from latest-PASS attempt metadata.

Options:
  --id RUN_ID; --scope PATH; --output-dir PATH; --scheduler MODE; --cpus N
  --require-metrics LIST; --include-unmanaged; --allow-rejected-vdb
  --timeout SEC; --idle-timeout SEC; --show-output

Examples:
  ./run.sh merge-cov --id <RUN_ID> --show-output
  ./run.sh merge-cov --scope sim/out/runs/<RUN_ID> --require-metrics line,group
EOF
            ;;
        view|wave)
            runner_wave_print_guide
            ;;
        summary)
            printf '%s\n' 'Summary: inspect saved dashboards and status data.' \
                'Options: --id, --burst-id, --attempt, --show, --tail.'
            ;;
        clean)
            printf '%s\n' 'Clean: remove an explicit artifact scope without touching source files.' \
                'Options: --temp, --all, --dump, --cov, --log, --report-only, --error, --id, --dry-run.'
            ;;
        generate)
            printf '%s\n' 'Generate: refresh the project filelist and normalized test plan.'
            ;;
        doctor)
            printf '%s\n' 'Doctor: validate project configuration, filelists, tools, and test-plan schema.'
            ;;
        list-tests)
            printf '%s\n' 'List-tests: print normalized tests with group, level, seeds, and tags.'
            ;;
        *)
            printf '[ERROR] Unknown help topic: %s\n\n' "$topic" >&2
            runner_help_summary
            return 2
            ;;
    esac
}

runner_print_help() {
    local topic="${1:-summary}"
    case "$topic" in
        ''|summary) runner_help_summary ;;
        --all|all)
            runner_help_summary
            local item
            for item in env comp test regression coverage merge-cov view; do
                printf '\n------------------------------------------------------------------------\n'
                runner_help_command "$item"
            done
            ;;
        *) runner_help_command "$topic" || return $? ;;
    esac
    runner_help_print_tests
}

if [[ ! -r "$RUNNER_SCRIPT_DIR/run_dispatch.sh" ]]; then
    echo "[ERROR] Missing dispatcher: $RUNNER_SCRIPT_DIR/run_dispatch.sh" >&2
    exit 2
fi

# shellcheck source=sim/vcs_run_script/run_dispatch.sh
source "$RUNNER_SCRIPT_DIR/run_dispatch.sh"

if [[ "${DV_RUNNER_REENTRY:-0}" == 1 ]]; then
    runner_dispatch "$@"
    exit $?
fi

reject_parallel_options() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            --worker|--worker=*|--jobs|--jobs=*|--auto-parallel|\
            --burst-max|--burst-max=*|--burst-jobs|--burst-jobs=*|\
            --burst-parallel|--cpoint-max|--cpoint-max=*|\
            --retry-wave-worker|--retry-wave-worker=*|\
            --retry-wave-burst-max|--retry-wave-burst-max=*|\
            --degraded-retry-worker|--degraded-retry-worker=*)
                echo "[ERROR] Parallel execution is not exposed by this handoff runner: $arg" >&2
                return 2
                ;;
        esac
    done
}

command="${1:-help}"
if (($# > 0)); then
    shift
fi
reject_parallel_options "$@" || exit $?

case "$command" in
    setup)
        runner_dispatch generate || exit $?
        runner_dispatch doctor
        ;;
    smoke)
        runner_dispatch test -t smc_i3c_csr_smoke_test --show-output "$@" || exit $?
        runner_dispatch test -t smc_i3c_sanity_test --show-output "$@"
        ;;
    target)
        runner_dispatch regression \
            -t smc_i3c_ibi_basic_test \
            -t smc_i3c_ibi_ack_nack_test \
            -t smc_i3c_ibi_mdb_payload_test \
            -t smc_i3c_ibi_fifo_irq_test \
            --worker 1 --burst-max 1 "$@"
        ;;
    controller)
        runner_dispatch regression \
            -t smc_i3c_ibi_controller_receive_test \
            -t smc_i3c_ibi_controller_content_test \
            -t smc_i3c_ibi_controller_policy_test \
            -t smc_i3c_ibi_controller_multi_target_test \
            -t smc_i3c_ibi_controller_timing_context_test \
            --worker 1 --burst-max 1 "$@"
        ;;
    regression)
        runner_dispatch regression --all --worker 1 --burst-max 1 "$@"
        ;;
    coverage)
        runner_dispatch coverage --all --worker 1 --burst-max 1 "$@"
        ;;
    signoff)
        echo "[ERROR] Signoff mode is not included in the handoff runner." >&2
        exit 2
        ;;
    *)
        runner_dispatch "$command" "$@"
        ;;
esac
