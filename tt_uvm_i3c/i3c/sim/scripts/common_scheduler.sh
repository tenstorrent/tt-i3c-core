#!/usr/bin/env bash

runner_resolve_scheduler() {
    local requested="${1:-auto}"
    case "$requested" in
        auto)
            if command -v srun >/dev/null 2>&1; then
                printf 'slurm\n'
            else
                printf 'local\n'
            fi
            ;;
        local|slurm) printf '%s\n' "$requested" ;;
        *) runner_die "Unsupported scheduler: $requested" ;;
    esac
}

runner_scheduler_job_name() {
    local value="dv_${DV_PROJECT_NAME:-project}_${RUNNER_ACTIVE_RUN_ID:-run}_${RUNNER_ACTIVE_BURST_ID:-job}_${RUNNER_ACTIVE_TEST:-task}_${RUNNER_ACTIVE_SEED:-x}"
    value="$(runner_sanitize_token "$value")"
    printf '%.100s\n' "$value"
}

runner_scheduler_snapshot() {
    local scheduler="$1" job_name="$2"
    [[ "$scheduler" == slurm ]] || return 1
    command -v squeue >/dev/null 2>&1 || return 1
    squeue -h -n "$job_name" -o '%A|%T|%P|%N|%R' 2>/dev/null | head -n 1
}

runner_scheduler_cancel() {
    local scheduler="$1" job_id="$2" report_mode="${3:-warning}"
    [[ "$scheduler" == slurm && -n "$job_id" ]] || return 0
    if command -v scancel >/dev/null 2>&1; then
        if [[ "$report_mode" == clean ]]; then
            printf '[CLEAN] cancel scheduler=slurm job=%s\n' "$job_id"
        else
            runner_warn "Cancelling Slurm job=$job_id"
        fi
        scancel "$job_id" 2>/dev/null || true
    fi
}

runner_scheduler_state_class() {
    case "${1^^}" in
        PENDING|CONFIGURING|RESV_DEL_HOLD|REQUEUE_HOLD) printf 'PENDING\n' ;;
        RUNNING|COMPLETING|STAGE_OUT) printf 'RUNNING\n' ;;
        COMPLETED) printf 'COMPLETED\n' ;;
        FAILED|CANCELLED*|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY|PREEMPTED) printf 'FAILED\n' ;;
        *) printf 'UNKNOWN\n' ;;
    esac
}

runner_build_scheduled_command() {
    local scheduler="$1" cpus="$2" x11="$3" interactive="$4"
    shift 4
    RUNNER_COMMAND=()
    RUNNER_ACTIVE_SCHEDULER="$scheduler"
    RUNNER_ACTIVE_JOB_NAME=''

    case "$scheduler" in
        local)
            RUNNER_COMMAND=("$@")
            ;;
        slurm)
            command -v srun >/dev/null 2>&1 || runner_die "srun is not available"
            RUNNER_ACTIVE_JOB_NAME="$(runner_scheduler_job_name)"
            RUNNER_COMMAND=(srun "--cpus-per-task=$cpus" "--job-name=$RUNNER_ACTIVE_JOB_NAME" --kill-on-bad-exit=1)
            [[ -n "${RUNNER_SLURM_EXPORT:-}" ]] && RUNNER_COMMAND+=(--export "$RUNNER_SLURM_EXPORT")
            [[ -n "${RUNNER_SLURM_PARTITION:-}" ]] && RUNNER_COMMAND+=(--partition "$RUNNER_SLURM_PARTITION")
            [[ -n "${RUNNER_SLURM_TIME:-}" ]] && RUNNER_COMMAND+=(--time "$RUNNER_SLURM_TIME")
            [[ -n "${RUNNER_SLURM_MEMORY:-}" ]] && RUNNER_COMMAND+=(--mem "$RUNNER_SLURM_MEMORY")
            [[ "$x11" == "1" ]] && RUNNER_COMMAND+=(--x11)
            if [[ "$interactive" == "1" && -t 0 && -t 1 ]]; then
                RUNNER_COMMAND+=(--pty)
            fi
            RUNNER_COMMAND+=("$@")
            ;;
    esac
}
