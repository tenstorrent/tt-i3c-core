#!/usr/bin/env bash

_DV_RUNNER_SOURCED=0
[[ "${BASH_SOURCE[0]}" != "$0" ]] && _DV_RUNNER_SOURCED=1

_dv_runner_source_usage() {
    cat <<'EOF'
Usage when sourced:
  source ./run.sh --link [--rc-file <path>]
  source ./run.sh completion bash

Sourced mode only activates Bash completion. Execute run.sh normally for
compile, test, regression, coverage, wave, and cleanup commands.
EOF
}

_dv_runner_source_completion() {
    local root="$1" completion="$1/i3c/sim/scripts/run_completion.bash"
    [[ -r "$completion" ]] || { echo "[ERROR] Completion script not found: $completion" >&2; return 1; }
    # shellcheck source=/dev/null
    source "$completion"
    echo "[INFO] Activated Bash completion in the current shell."
}

if ((_DV_RUNNER_SOURCED)); then
    _dv_runner_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    _dv_runner_status=0
    case "${1:-}" in
        --link)
            shift
            bash "$_dv_runner_root/run.sh" --link "$@" || _dv_runner_status=$?
            ((_dv_runner_status == 0)) && _dv_runner_source_completion "$_dv_runner_root" || true
            ;;
        completion)
            if [[ "${2:-}" == bash ]]; then
                _dv_runner_source_completion "$_dv_runner_root" || _dv_runner_status=$?
            else
                _dv_runner_source_usage >&2
                _dv_runner_status=2
            fi
            ;;
        ''|help|-h|--help) _dv_runner_source_usage ;;
        *)
            echo "[ERROR] source ./run.sh only supports --link or completion bash" >&2
            _dv_runner_source_usage >&2
            _dv_runner_status=2
            ;;
    esac
    unset -f _dv_runner_source_usage _dv_runner_source_completion
    unset _DV_RUNNER_SOURCED _dv_runner_root
    return "$_dv_runner_status"
fi

set -uo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER_ROOT="$PACKAGE_ROOT/i3c"
RUNNER_REPORT_ROOT="$PACKAGE_ROOT"
RUNNER_SCRIPT_DIR="$RUNNER_ROOT/sim/scripts"
DV_RUNNER_ENTRYPOINT="$PACKAGE_ROOT/run.sh"
export PACKAGE_ROOT RUNNER_ROOT RUNNER_REPORT_ROOT RUNNER_SCRIPT_DIR DV_RUNNER_ENTRYPOINT

if [[ "${1:-}" == "--project" ]]; then
    [[ $# -ge 2 ]] || { echo "[ERROR] --project requires a configuration path" >&2; exit 2; }
    export DV_PROJECT_CONFIG="$2"
    shift 2
fi

# shellcheck source=sim/scripts/project_config.sh
source "$RUNNER_SCRIPT_DIR/project_config.sh"
runner_project_load || exit $?

runner_help_summary() {
    local help_title="${DV_HELP_TITLE:-Generic DV Runner}"
    local help_scope="${DV_HELP_SCOPE:-Project}"
    local example_test="${DV_HELP_EXAMPLE_TEST:-smoke_test}"
    local help_tool_setup="${DV_HELP_TOOL_SETUP:-module load vcs verdi}"
    local help_dep_root_var="${DV_HELP_DEP_ROOT_VAR:-DV_DEPS_ROOT}"
    cat <<EOF
$help_title

Usage:
  ./run.sh <command> [options]
  ./run.sh help <command>

First run setup:
  Load simulator and waveform tools:
    $help_tool_setup

  Configure the project dependency checkout when it is not in the default location:
    export $help_dep_root_var=/path/to/dependencies

  Optional Bash completion:
    source ./run.sh --link

  Generate inputs, validate the environment, compile, and inspect available tests:
    ./run.sh generate
    ./run.sh doctor
    ./run.sh compile --show-output
    ./run.sh list-tests

Commands:
  compile      Compile. Options: --scheduler, --cpus, --cov, --dump-format, --show-output
  test         Single test. Options: -t, --seed/--seeds, --cov, --dump-format, --show-output
  regression   Regression. Options: --all/-t/-g, --rand-num, --worker, --burst-max, --cov
  coverage     Coverage regression/closure. Supports regression options, --target, --waiver
  merge-cov    Merge VDBs and manage waiver files. Options: --id, --waiver, --waiver-create
  view         List/open runs, waves, logs, or merged coverage databases
  summary      List run summary paths or show details. Options: --id, --limit, --fail, --html, --tail
  clean        Scoped cleanup. Options: --temp, --all, --dump, --cov, --log, --view, --id
  generate     Generate project filelists and normalized test plan
  signoff      Run coverage closure followed by regression; supports --waiver
  doctor       Validate project and runner configuration
  self-test    Run tool-independent runner qualification
  list-tests   Print the current normalized test list
  jobs         List managed jobs; stop-jobs stops them

$help_scope quick examples (using $example_test):
  Compile:
    ./run.sh compile --scheduler slurm

  Run one test and stream simulator output:
    ./run.sh test -t $example_test --show-output

  Run one test with coverage, FSDB, and simulator output:
    ./run.sh test -t $example_test --cov --dump-format fsdb --show-output

  Run every enabled regression entry:
    ./run.sh regression --all

  Run a full random regression:
    ./run.sh regression --all --rand-num 10 --worker 2 --burst-max 4

  Run coverage with the same regression parallelism:
    ./run.sh coverage --all --rand-num 10 --worker 2 --burst-max 4

  Run coverage and automatically create raw plus waiver-adjusted reports:
    ./run.sh coverage --all --waiver-file <REVIEWED_EL> --waiver-manifest <REVIEWED_TSV> --target 100

  Merge latest-PASS coverage databases:
    ./run.sh merge-cov --id <RUN_ID> --show-output

  Create, check, and promote a reviewed Verdi exclusion file:
    ./run.sh merge-cov --id <RUN_ID> --waiver-create --waiver-source <EXPORTED_EL> --waiver-manifest <REVIEWED_TSV>
    ./run.sh merge-cov --id <RUN_ID> --waiver-check --waiver-manifest <REVIEWED_TSV>
    ./run.sh merge-cov --id <RUN_ID> --waiver-promote --waiver-file <REVIEWED_EL> --waiver-manifest <REVIEWED_TSV>

  List and open waveforms:
    ./run.sh view --runs
    ./run.sh view --run-id <RUN_ID>
    ./run.sh view
    ./run.sh view --open --last --fsdb

  List and open merged coverage through Slurm/X11:
    ./run.sh view --coverage --runs
    ./run.sh view --coverage --latest-run --open
    ./run.sh view --coverage --run-id <RUN_ID> --variant raw --open

More:
  ./run.sh help doctor|comp|test|regression|coverage|merge-cov|view
  ./run.sh <command> --help
  ./run.sh help --all
  Read docs/user-guide/REFERENCE_RUNNER.md for execution and artifact contracts.

Tests:
  ./run.sh list-tests                         # first 20 entries
  ./run.sh list-tests --page 2                # another page
  ./run.sh list-tests --page-size 40          # recalculate page size
  ./run.sh list-tests --all                   # every entry
EOF
}

runner_help_command() {
    local topic="$1"
    local example_test="${DV_HELP_EXAMPLE_TEST:-smoke_test}"
    local sanity_test="${DV_HELP_SANITY_TEST:-sanity_test}"
    local help_scope="${DV_HELP_SCOPE:-Project}"
    case "$topic" in
        comp|compile)
            cat <<EOF
Compile
  Build one isolated VCS simulation image. Compile defaults to four VCS jobs.

Usage:
  ./run.sh compile [--scheduler MODE] [--cpus N] [--cov]
                   [--dump-format none|vcd|vpd|fsdb] [--show-output]

Examples:
  ./run.sh compile --scheduler slurm
  ./run.sh compile --scheduler slurm --cpus 4 --show-output
  ./run.sh compile --cov --dump-format fsdb --show-output
EOF
            ;;
        test)
            cat <<EOF
Single Test
  Compile once and run one test over one or more seeds.

Options:
  -t, --test NAME; --seed N; --seeds LIST; --rand-num N; --worker N
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
  --all; -t, --test NAME; --case ID; -g, --group NAME; --level NAME; --include-off
  --seeds LIST; --rand-num N for random-seed plan entries; --worker N; --burst-max N
  --case-order auto|test-major|seed-major
  --cov; --dump-format FORMAT; --scheduler MODE; --show-output
  --attempt-retry-max N; --seed-retry-max N; --retry-schedule MODE

Examples:
  ./run.sh regression --all
  ./run.sh regression --all --rand-num 10 --worker 2 --burst-max 4
  ./run.sh regression --all --rand-num 10 --case-order seed-major
  ./run.sh regression -g smoke --seeds 1,2,3 --worker 2 --burst-max 2
EOF
            ;;
        coverage|cov)
            cat <<EOF
Coverage
  Run a single test or regression with coverage, then merge latest-PASS VDBs.

Options:
  All regression selectors and parallel options are supported.
  --rand-num replaces seeds only for test-plan entries tagged random-seed.
  Coverage regression defaults to seed-major; --case-order can override it.
  --target PERCENT; --target-metric NAME; --max-seeds N
  --check-interval N; --allow-miss; --skip-merge; --show-output
  --waiver; --waiver-file FILE; --waiver-manifest FILE

Examples:
  ./run.sh coverage -t $example_test --show-output
  ./run.sh coverage --all --rand-num 10 --worker 2 --burst-max 4
  ./run.sh coverage --all --target 95 --max-seeds 10 --worker 2 --burst-max 4
  ./run.sh coverage --all --waiver-file <REVIEWED_EL> --waiver-manifest <REVIEWED_TSV> --target 100
EOF
            ;;
        merge-cov)
            cat <<'EOF'
Coverage Merge
  Merge compile/runtime VDBs selected from latest-PASS attempt metadata.

Options:
  --id RUN_ID; --scope PATH; --output-dir PATH; --scheduler MODE; --cpus N
  --require-metrics LIST; --include-unmanaged; --allow-rejected-vdb
  --waiver; --waiver-file FILE; --waiver-manifest FILE
  --waiver-create --waiver-source EXPORTED_EL; --waiver-check; --waiver-promote
  --timeout SEC; --idle-timeout SEC; --show-output

Examples:
  ./run.sh merge-cov --id <RUN_ID> --show-output
  ./run.sh merge-cov --id <RUN_ID> --waiver-file <REVIEWED_EL> --waiver-manifest <REVIEWED_TSV>
  ./run.sh merge-cov --id <RUN_ID> --waiver-create --waiver-source <EXPORTED_EL> --waiver-manifest <REVIEWED_TSV>
  ./run.sh merge-cov --id <RUN_ID> --waiver-check --waiver-manifest <REVIEWED_TSV>
  ./run.sh merge-cov --id <RUN_ID> --waiver-promote --waiver-file <REVIEWED_EL> --waiver-manifest <REVIEWED_TSV>
  ./run.sh merge-cov --scope sim/out/runs/<RUN_ID> --require-metrics line,group
EOF
            ;;
        view|wave)
            runner_wave_print_guide
            ;;
        summary)
            cat <<'EOF'
Summary
  List summary paths for recent runs, inspect saved data, or show failed logs.

Options:
  --id, --run-id RUN_ID   Select one run; default lists recent runs.
  --limit N               Limit the default run index (default: 10).
  --burst-id BNNN         Restrict the summary to one burst.
  --attempt ANNN          Restrict the summary to one attempt.
  --tail N                Print the last N lines of each detailed summary file.
  --show                  Print complete summary files.
  --fail, --failures      Print only each failed test name and its simulation log path.
  --html                  Print or generate the selected run's HTML summary path.

Examples:
  ./run.sh summary
  ./run.sh summary --limit 5
  ./run.sh summary --id <RUN_ID>
  ./run.sh summary --id <RUN_ID> --html
  ./run.sh summary --tail 40
  ./run.sh summary --id <RUN_ID> --fail
  ./run.sh summary --id <RUN_ID> --burst-id B003 --attempt A002
EOF
            ;;
        clean)
            printf '%s\n' 'Clean: remove an explicit artifact scope without touching source files.' \
                'Options: --temp, --all, --dump, --cov, --log, --view, --report-only, --error, --id, --dry-run, --show-output.'
            ;;
        generate)
            printf '%s\n' 'Generate: refresh the project filelist and normalized test plan.'
            ;;
        signoff)
            printf '%s\n' 'Signoff: run coverage closure, then regression.' \
                'Options: --target, --waiver, -t/--test, -g/--group, --all, --worker, --burst-max.'
            ;;
        doctor)
            printf '%s\n' 'Doctor: validate project configuration, filelists, tools, and test-plan schema.'
            ;;
        self-test)
            printf '%s\n' 'Self-test: run the tool-independent qualification suite for the runner.'
            ;;
        list-tests)
            cat <<'EOF'
List-tests: browse the normalized test plan without expanding the main help.
  ./run.sh list-tests
  ./run.sh list-tests --page 2 --page-size 20
  ./run.sh list-tests --head|--tail
  ./run.sh list-tests --all
  ./run.sh list-tests --all --format raw
Set RUNNER_TEST_PAGE_SIZE to change the default page size for the shell.
EOF
            ;;
        jobs|stop-jobs)
            printf '%s\n' 'Jobs: list managed processes. Stop-jobs terminates all managed processes.'
            ;;
        *)
            printf '[ERROR] Unknown help topic: %s\n\n' "$topic" >&2
            runner_help_summary
            return 2
            ;;
    esac
}

runner_print_help() {
    local topic="${1:-}"
    case "$topic" in
        '') runner_help_summary ;;
        summary) runner_help_command summary ;;
        --all|all)
            runner_help_summary
            local item
            for item in comp test regression coverage merge-cov view summary; do
                printf '\n------------------------------------------------------------------------\n'
                runner_help_command "$item"
            done
            ;;
        *) runner_help_command "$topic" || return $? ;;
    esac
}

if [[ ! -r "$RUNNER_SCRIPT_DIR/run_dispatch.sh" ]]; then
    echo "[ERROR] Missing dispatcher: $RUNNER_SCRIPT_DIR/run_dispatch.sh" >&2
    exit 2
fi

# shellcheck source=sim/scripts/run_dispatch.sh
source "$RUNNER_SCRIPT_DIR/run_dispatch.sh"
runner_dispatch "$@"
