# Optional Reference VCS DV Runner

This directory contains the optional reference orchestration used to reproduce
the package's validated VCS flows. It is not a runtime dependency of the UVM
environment and is not intended to replace DVSim or an integrator's existing
regression framework. The simulator-independent integration contract is in
`docs/user-guide/EXTERNAL_RUNNER.md` at the package root.

Use
`./run.sh help` for the project quick-start page, `./run.sh help <command>` or
`./run.sh <command> --help` for command-level options, and
`./run.sh help --all` for every help tier. Project and IP knowledge belongs in
`sim/dv_project.sh`, generated inputs, and project hooks. `./run.sh view`
prints compact examples before the current artifact listing.

Install context-aware Bash completion once with:

```bash
source ./run.sh --link
```

Linked completion covers every public runner option and command alias, offers
test, case, and group names from the generated test plan, and
suggests valid values for enumerated options such as scheduler, dump format,
case order, retry schedule, log style, and coverage variant.

For plan-driven regression, coverage, and signoff, `--rand-num` only replaces
the seeds of entries tagged `random-seed`; directed entries retain their plan
seeds. `--coverage-rand-num` and `--regression-rand-num` inherit that rule.
Explicit `--seeds` intentionally overrides every selected entry. Direct
single-test execution (`run.sh test --rand-num`) remains an explicit request to
randomize that named test and therefore does not apply the plan filter.

The main help stays compact and keeps the normalized test plan separate.
`./run.sh list-tests` shows the first 20 entries; use `--page N`,
`--page-size N`, `--head`, or `--tail` to navigate, and `--all` to show every
entry. `RUNNER_TEST_PAGE_SIZE` changes the shell default without modifying the
repository. Automation should use `./run.sh list-tests --all --format raw`.
Human listings use one line per entry, zero-pad its global index to the width
of the total entry count, and label test and case as `T` and `C`. Test and case
have minimum widths of 60 and 40 characters; longer values are not truncated.
Plusargs are rendered as the directly reusable CLI fragment
`--plusargs "+ARG=value"`; shell-sensitive characters are escaped inside the
double-quoted value. A generated case ID equal to its test name is displayed
as `C=-` without changing the stored selector. Status padding stays outside
the brackets: `[ON]  ` and `[OFF] ` align the following `T=`.

The sourced form updates the selected rc file and activates the current shell.
The executed form, `./run.sh --link`, updates future shells only. Use
`--rc-file <path>` when `~/.bashrc` is not the desired target.

## Execution Contract

- VCS is the only simulator backend.
- Compile defaults to four scheduled CPUs and VCS `-j4`; each simulation seed
  still defaults to one CPU. `./run.sh compile --cpus N` changes both the compile
  allocation and VCS parallel compile count. Set `DV_DEFAULT_COMPILE_JOBS` to
  override the compile default without changing simulation CPU allocation.
- The runner is the only local/Slurm scheduler owner; project Makefiles must not
  call `srun`.
- Each regression burst compiles into a private build directory. Seeds in that
  burst reuse its image. No build is shared across bursts.
- A source test list may declare simulator-neutral per-test compile needs with
  `# TEST_REQUIRES_COMPILE <test>=<requirement>`. The normalized plan carries
  them into the burst manifest. Currently `hdl_access` maps to VCS
  `-debug_access+all`; tests without that requirement retain the normal light
  compile. Direct test and regression flows apply the same mapping.
- Regression defaults to the per-level `BURST_PLAN` metadata in the normalized
  test plan. `test-major` finishes one test across seed chunks whose sizes come
  from `BURST_LIMITS`; `seed-major` finishes all selected tests for one seed
  before advancing to the next seed. `--case-order` overrides the metadata.
- Coverage regression defaults to `seed-major` so every selected test sees the
  same random seed before closure advances. A direct `--case-order` option wins.
- Every seed and retry attempt has private run-work, log, dump, and VDB paths.
- Waveform creation is reported independently as `CREATED`, `MISSING`,
  `DISABLED`, or `DRY_RUN`; a missing optional dump never rewrites the
  simulator/UVM functional verdict.
- FSDB compilation defaults to `DV_FSDB_COMPILE_STYLE=integrated`, using
  `-kdb -debug_access+all` and `VERDI_HOME` for current VCS/Verdi releases. Set the
  style to `legacy` only for installations that still require
  `-P novas.tab pli.a`.
- Dump support is compiled per run format: VPD adds its guarded VCS system
  tasks and debug access, FSDB adds its own guarded system tasks and selected
  integration, while `none` and VCD do not pay that compile cost. Do not reuse
  a build with `--no-comp` when changing dump format.
- Slurm job ID/state/partition/node are recorded when `squeue` is available;
  stop and clean operations call `scancel` before terminating local wrappers.
- Hang protection terminates local, Slurm `PENDING`, and Slurm `RUNNING` jobs
  after their configured no-progress windows. `HANG-WARN` and `HANG-FAIL`
  notices bypass compact worker-log capture and remain visible on the
  controlling terminal. Set `RUNNER_ALLOW_REMOTE_HANG_KILL=0` for an
  intentionally quiet long-running Slurm invocation that must not be killed.
- Coverage merge selects VDBs only from the latest PASS attempt metadata.
  `--include-unmanaged` is an explicit review override.
- Coverage compiles create a dedicated `compile.vdb`. Managed merges include
  that design database before per-attempt runtime VDBs and reject missing
  compile-time design data.
- Coverage merge rejects incompatible VDBs by default. Use
  `--allow-rejected-vdb` only after reviewing `rejected_vdbs.tsv`.
- URG metrics are mapped by either text or HTML dashboard headers.
  `--require-metrics` or
  `DV_REQUIRED_COVERAGE_METRICS` can require code, assertion, or group columns
  before a merge is accepted.
- Coverage summaries always render the canonical `SCORE`, `LINE`, `COND`,
  `TOGGLE`, `FSM`, `BRANCH`, `ASSERT`, and `GROUP` rows. A metric that
  is absent from the URG report is shown as `N/A`; a measured but unhit metric
  remains a numeric `0.00%`.
- `ASSERT` is the URG assertion-coverage percentage. It is independent from
  `SVA Error`, which counts runtime assertion failures and affects the verdict.
- Coverage waivers are opt-in. `coverage`, `merge-cov`, and `signoff` accept
  `--waiver` (alias `--apply-waivers`). The runner always produces the raw URG
  report first, then uses the project `DV_COV_WAIVER_FILE` for a separate
  adjusted report. The target is evaluated against the adjusted metric only
  when this option is present.
- An adjusted report is accepted only when the exclusion file has active URG
  rules and every entry in `DV_COV_WAIVER_MANIFEST` is `REVIEWED` or
  `APPROVED`. The result includes `waivers_applied.txt`, raw/adjusted metrics,
  source scopes, reasons, evidence, and an exclusion-file hash. Raw reports are
  retained under the coverage result's `raw/` directory.
- A reviewed Verdi exclusion can be installed without editing runner sources.
  `merge-cov --id RUN --waiver-create --waiver-source FILE` copies and validates
  the exported rules as a run-local candidate. `--waiver-check` validates that
  candidate (or the canonical project file when no candidate exists), and
  `--waiver-promote` backs up then replaces `DV_COV_WAIVER_FILE`. Subsequent
  `coverage`, `merge-cov`, and `signoff --waiver` runs reuse the promoted file.
- `view --runs` lists known run IDs with type, status, test, waveform, and VDB
  counts. `view --run-id RUN` filters artifacts to one run, while
  `view --latest-run` selects the newest run without confusing it with `--last`,
  which selects the newest matching artifact.
- `view --coverage --runs` lists merged coverage databases without requiring a
  manual `find`. `--run-id RUN` and `--latest-run` select a result, while
  `--variant auto|raw|adjusted` selects the database view. `auto` prefers the
  waiver-adjusted database, then a regular merge, then the retained raw merge.
  `--open` launches `verdi -cov -covdir DATABASE` exclusively through Slurm
  with X11 and `--export=ALL`; it never executes the coverage GUI directly on
  the login node. `--elfile FILE` loads a reviewed or work-in-progress Verdi
  exclusion file with that database.
- Each coverage viewer uses `sim/out/view/coverage/RUN_ID` as its working
  directory. Vendor-created `verdiLog`, `novas.*`, session files, and launch
  metadata therefore remain under `sim/out` instead of polluting the active
  project root. Close the viewer before using `clean --view`; `clean --temp`
  also removes viewer workspaces, while `clean --all` removes the complete
  output tree. `clean --view --id RUN_ID` removes only one coverage-view
  workspace and does not remove its merged VDB or exclusion file. These clean
  modes also remove Verdi-generated `.fsm.sch.verilog.xml` files from the active
  project tree when they were created outside `sim/out`; files already below
  `sim/out` are handled by the normal output cleanup and are not scanned twice.

## Output Contract

All commands print the command/environment panel before dispatch and summary
panels at completion. Composite regression, coverage, and signoff commands
default to compact parent output containing per-test-and-seed plans,
case-level START/PASS/FAIL rows, heartbeat, phase, retry, and final status
lines. Bursts remain the compile, scheduling, and burst-retry boundary.
Use `--log-style verbose` or `--show-worker-output` to restore plans and worker
output in the terminal. Both styles store the same detailed artifacts:

```text
<run-or-burst-attempt>/
|-- summary/
|   `-- <human-readable status, errors, and quick links>
|-- metadata/
|   |-- run.meta
|   |-- compile.meta
|   |-- testplan.snapshot.dv
|   |-- manifest.tsv, status.tsv, case_status.tsv
|   `-- commands/compile.sh
|-- compile_logs/compile.log
|-- tests/<test>/seed_<seed>/attempt_<n>/
|   |-- logs/sim.log
|   |-- coverage/
|   `-- dumps/
`-- <flow-specific artifacts>
```

`compile_logs` contains compile/job logs at the enclosing attempt scope.
`tests` contains per-test and per-seed execution artifacts; the nested `logs`
directory contains simulation logs only. `summary` is the human entry point:
its default output lists recent Run IDs with four indented paths for the main
summary, failures, coverage, and artifact index. `summary --show` and
`summary --tail N` read detailed content, while `summary --fail` reduces the
selected run to failed test names and their simulation-log paths.
Each completed compile, single-test, regression, or coverage run also publishes
`summary/run_summary.html`. The static dashboard is generated from TSV status
data, uses relative links to available logs and dumps, and does not alter the
functional verdict if optional HTML generation fails. Use
`./run.sh summary --id <RUN_ID> --html` to locate it.
`metadata` stores machine-readable provenance, plan snapshots, and replayable
run-level commands. A per-test `command.sh` remains in its attempt directory.
Readers retain fallback support for historical runs that stored metadata at the
run root and used `logs/compile` and `cases`, but all newly created runs use the
layout above.

Coverage and signoff runs keep coverage closure and execution triage separate.
The generated I3C test plan also enforces functional sampling with
`+IBI_REQUIRE_COV` for coverage, random, multi-target, and positive WIP IBI
groups. Reset-flush, invalid-target, busy-bus and soft-reset defect scenarios
carry a `coverage-exempt` tag because their correct negative path may produce
no accepted IBI event. These exceptions remain visible in `sim/generated/testplan.dv`.
`summary/coverage.log` contains the target, waiver state, report links, and the
canonical coverage metrics. `summary/regression.log` aggregates every coverage
iteration and records `Iteration`, test, seed, attempts, verdict, diagnostics,
and the simulation-log path for every case. `summary/failures.log` is the short
index of failed cases only. The coverage summary links to both execution logs;
an iteration with no failures is still retained in the complete regression log.

SMC I3C coverage builds are intentionally IBI-only: the backend compiles with
`SMC_I3C_IBI_COVERAGE_ONLY`, applies `sim/scripts/cov_setup.cfg`, and collects
only IBI-prefixed testplan entries for coverage closure. Smoke and RAL entries
remain enabled for ordinary regressions. The project requires only the URG
`ASSERT` and `GROUP` columns: the backend collects only the VCS `assert` metric
plus UVM functional covergroups. RTL line, condition, toggle, FSM, and branch
coverage are disabled for this closure run.

`smc_i3c_boundary_sva` is also outside the IBI coverage denominator. Its five
stability assertions require directed AXI backpressure and its two denied-access
assertions require `access_allow=0`; those are owned by a separate AXI/CSR
boundary verification scope. The module remains available in ordinary
non-coverage builds and is not waived or counted as IBI evidence.

- `metadata/run.meta`, `metadata/compile.meta`, and replayable command files;
- compile metadata records the exact top, filelist, compile working directory,
  source revision, and Verdi debug database used by waveform source mapping;
- canonical ANSI-free tool logs and adjacent `*.clean.log` compatibility copies;
- simulator-colored live output when `--show-output` is enabled; stored logs remain ANSI-free;
- `seeds.tsv`, burst `status.tsv`, case `case_status.tsv`, manifests,
  summaries, and error extracts;
- `case_status.tsv` stores `test`, `case_id`, `level`, and `plusargs` as
  separate machine-readable columns; human regression and failure summaries
  spell those labels out instead of using the compact terminal abbreviations;
- `artifacts.tsv` linking logs, commands, waves, reports, and databases;
- compact waveform listings indexed by run, test, seed, and attempt, with
  project-relative paths and same-attempt log mapping;
- Verdi source mapping defaults to `auto`: use the matching KDB when available,
  otherwise reparse the recorded filelist. `--source-map off` opens waveform
  only, while `--source-map reparse` requires a valid source context;
- VCD-to-FSDB conversion keeps the converted waveform, captured converter
  output, and vendor-created `vcd2fsdbLog` directory under the attempt's
  `dumps/.wave_cache` tree;
- `vdb_manifest.tsv`, URG metric matrix, and `rejected_vdbs.tsv` when needed;
- for `--waiver`, `raw/report`, adjusted `report`, `waiver.meta`, and
  `waivers_applied.txt`.

Test results distinguish UVM, assertion, scoreboard, license, disk, scheduler,
timeout, and simulator failures. Retried passes are reported separately.

## Legacy Boundary

Project-owned historical scripts may remain beside this runner during
qualification. They are not active unless the public `run.sh` dispatches them.
Do not copy orchestration behavior from a legacy script into a project adapter;
extend the generic runner and its tool-independent self-test instead.

Validate changes with:

```bash
./run.sh --project examples/minimal/dv_project.sh doctor
./run.sh --project examples/minimal/dv_project.sh self-test
```
