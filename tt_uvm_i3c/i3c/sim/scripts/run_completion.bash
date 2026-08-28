#!/usr/bin/env bash

_generic_dv_runner_completion() {
    local current previous root completion_values
    current="${COMP_WORDS[COMP_CWORD]}"
    previous="${COMP_WORDS[COMP_CWORD-1]}"
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

    local commands='--link link-completion generate gen comp compile test regression regress coverage cov merge-cov signoff view wave summary clean list-tests jobs stop-jobs doctor check source self-test completion help'
    local options='-h --help --link --rc-file --scheduler --cpus --timeout --idle-timeout --show-output --show-worker-output --log-style --compact-log --verbose-log --detach --x11 --no-x11 --heartbeat-sec --hang-warn-sec --hang-kill-sec --hang-pending-kill-sec --hang-min-elapsed-sec --hang-low-cpu-pct --live-mode --live-overwrite --live-line --live-quiet'
    options+=' -t --test -s --seed --seeds -r --rand-num -p --parallel -v --verb --jobs --worker --retry-max --seed-retry-max --plusargs --extra-run-opts --dump --dump-format --cov --conn --verbosity --include-warnings --no-comp --run-only --id --run-id --run-dir -f --file'
    options+=' -g --group --label --case --level --exclude-test --exclude-group --exclude-label --all --include-off --list-groups --burst-max --burst-parallel --cpoint-max --burst-jobs --burst-delay-sec --burst-start-gap-sec --case-order --attempt-retry-max --no-attempt-retry --attempt-retry-delay-sec --retry-schedule --retry-immediate --retry-deferred-wave --retry-wave-burst-max --retry-wave-worker --degraded-retry --no-degraded-retry --degraded-retry-mode --degraded-retry-delay-sec --degraded-retry-worker --no-degraded-retry-clean --rerun-burst --rerun-failed --list-bursts'
    options+=' --target --coverage-target --target-metric --coverage-metric --max-seeds --check-interval --stop-on-target --no-stop-on-target --allow-miss --allow-coverage-miss --no-merge --skip-merge --skip-report --probe --include-unmanaged --no-isolate-bad-vdb --allow-rejected-vdb --require-metrics --waiver --apply-waivers --waiver-file --waiver-manifest --waiver-create --waiver-source --waiver-check --waiver-promote'
    options+=' --coverage-seeds --coverage-rand-num --regression-seeds --regression-rand-num --phase-wait-sec --inter-phase-wait-sec --regression-exclude-label --regression-exclude-test --include-coverage-tests-in-regression'
    options+=' -d --d -l --l --log -c --c -o --format --wave-format --fsdb --vcd --vpd --any-dump --last --open --run --tail --show --show-log --show-compile --open-log --open-compile --viewer --source-map --no-source-map --limit --runs --list-runs --latest-run --coverage --cov-db --variant --coverage-variant --elfile --exclusion-file --compile'
    options+=' --temp --build --view --report-only --error --attempt-failed --failed-attempts --fail --failures --burst --burst-id --attempt --pid --force --dry-run --page --page-size --head -a --a'
    options+=' --scope --output-dir --build-dir --build-subdir --log-dir --log-subdir --summary-dir --summary-subdir --cov-dir --dump-dir --compile-requirements'
    options+=' --caliptra --root --from'

    if ((COMP_CWORD == 1)); then
        COMPREPLY=( $(compgen -W "$commands" -- "$current") )
        return
    fi

    if [[ "${COMP_WORDS[1]:-}" == source && $COMP_CWORD -eq 2 ]]; then
        COMPREPLY=( $(compgen -W 'set mode show pin reset help' -- "$current") )
        return
    fi
    if [[ "${COMP_WORDS[1]:-}" == source && "${COMP_WORDS[2]:-}" == mode ]]; then
        COMPREPLY=( $(compgen -W 'pinned latest worktree snapshot' -- "$current") )
        return
    fi

    if [[ "$previous" == '-t' || "$previous" == '--test' ]]; then
        completion_values="$(bash "$root/run.sh" completion tests 2>/dev/null)"
        COMPREPLY=( $(compgen -W "$completion_values" -- "$current") )
        return
    fi
    if [[ "$previous" == '--case' ]]; then
        completion_values="$(bash "$root/run.sh" completion cases 2>/dev/null)"
        COMPREPLY=( $(compgen -W "$completion_values" -- "$current") )
        return
    fi
    if [[ "$previous" == '-g' || "$previous" == '--group' || "$previous" == '--label' ]]; then
        completion_values="$(bash "$root/run.sh" completion groups 2>/dev/null)"
        COMPREPLY=( $(compgen -W "$completion_values" -- "$current") )
        return
    fi
    if [[ "$previous" =~ ^--(rc-file|file|waiver-file|waiver-manifest|waiver-source|elfile|exclusion-file|output-dir|run-dir|build-dir|log-dir|summary-dir|cov-dir|dump-dir|root|from|caliptra)$ ]]; then
        COMPREPLY=( $(compgen -f -- "$current") )
        return
    fi
    case "$previous" in
        --source-map) completion_values='auto off reparse' ;;
        --scheduler) completion_values='local slurm' ;;
        --dump-format) completion_values='none vcd vpd fsdb' ;;
        --wave-format) completion_values='any vcd vpd fsdb' ;;
        --format)
            if [[ "${COMP_WORDS[1]:-}" == list-tests ]]; then completion_values='human raw'
            else completion_values='any vcd vpd fsdb'
            fi
            ;;
        --log-style) completion_values='compact verbose' ;;
        --case-order) completion_values='auto test-major seed-major' ;;
        --retry-schedule) completion_values='immediate deferred-wave' ;;
        --live-mode) completion_values='overwrite line quiet' ;;
        --level) completion_values='light medium heavy extra' ;;
        --variant|--coverage-variant) completion_values='auto raw adjusted' ;;
        --target-metric|--coverage-metric) completion_values='score assert group' ;;
        *) completion_values='' ;;
    esac
    if [[ -n "$completion_values" ]]; then
        COMPREPLY=( $(compgen -W "$completion_values" -- "$current") )
        return
    fi
    COMPREPLY=( $(compgen -W "$options" -- "$current") )
}

complete -F _generic_dv_runner_completion ./run.sh run.sh
