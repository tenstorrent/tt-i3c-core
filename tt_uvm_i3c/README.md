# TT UVM I3C Verification Environment

Standalone SystemVerilog/UVM verification environment for the Tenstorrent
(TT) I3C core. The package verifies both DUT roles:

- **Target-TX:** the TT RTL is an I3C Target that transmits an IBI; the I3C VIP
  acts as Controller and returns ACK or NACK.
- **Controller-RX:** the TT RTL is an I3C Controller; the I3C VIP acts as a
  Target and initiates an IBI toward the DUT.

The TT I3C RTL is deliberately not copied into this repository. A compatible,
recursive TT I3C checkout is selected through `I3C_ROOT_DIR`. The runner checks
that checkout but never fetches, edits, resets, or checks out RTL.

## Contents

1. [Overview](#1-overview)
2. [First-Time Setup](#2-first-time-setup)
3. [Quick Run Guide](#3-quick-run-guide)
4. [Runner Script Inventory](#4-runner-script-inventory)
5. [VNCHIP File Inventory](#5-vnchip-file-inventory)
6. [Using Another Runner or Simulator](#6-using-another-runner-or-simulator)

## 1. Overview

### 1.1 TT I3C Core

The selected TT core provides the I3C RTL, HCI/CSR implementation, Controller
and Target logic, and its recursive Caliptra RTL dependency. This repository
provides the verification environment around that RTL:

```text
AXI4-Lite VIP
      |
      v
smc_i3c_axi_adapter
      |
      v
smc_i3c_wrapper ---- TT I3C core
                         |
                         +---- SDA/SCL <----> I3C VIP
                         |
                         +---- IRQ/status ---> observer/predictor/scoreboard
                                              SVA and functional coverage
```

The internal `smc_*` names are retained from the qualified integration
baseline. They are a compatibility namespace and do not create a runtime
dependency on another OCAH project.

### 1.2 Integrated Components

| Component | Location | Purpose |
|---|---|---|
| Public runner | `run.sh` | Single entry point for setup, compile, tests, regression, coverage, summaries, and waves |
| VCS runner implementation | `i3c/sim/vcs_run_script/` | Local/Slurm execution, reporting, retry, coverage merge, and Verdi launch |
| AXI4-Lite VIP | `i3c/verify/vip/axi4lite_vip/` | Programs DUT CSRs and HCI registers |
| I3C VIP | `i3c/verify/vip/i3c_vip/` | Drives and monitors I3C Controller/Target bus behavior |
| UVM environment | `i3c/verify/tb/env/` | Agents, helpers, observers, predictors, and scoreboards |
| RAL | `i3c/verify/tb/ral/` | I3C register model and AXI4-Lite adapter |
| Tests and sequences | `i3c/verify/tb/tests/`, `i3c/verify/tb/vseq/` | CSR, Target-TX IBI, and Controller-RX IBI stimulus |
| SVA | `i3c/verify/tb/sva/` | AXI boundary and IBI protocol/role assertions |
| Functional coverage | `i3c/verify/tb/coverage/` | IBI attempt, completion, queue/IRQ, and generic access coverage |
| UVM library | `third_party/uvm-core-2020.3.1/` | Bundled UVM 2020.3.1 fallback |
| DUT integration | `i3c/rtl/` | AXI adapter, wrapper, external-core manifest, and stub mode |

The bundled I3C VIP retains its own license and provenance under
`i3c/verify/vip/i3c_vip/`. It is not represented as wholly authored by
VNCHIP. The TT RTL and Caliptra RTL remain external dependencies.

### 1.3 Implemented Verification

The current source contains:

| Metric | Implemented |
|---|---:|
| Runnable tests | 12 unique tests |
| Base test classes | 2, not run directly |
| DUT-Target IBI tests | 4 |
| DUT-Controller IBI tests | 5 |
| CSR/sanity tests | 3 |
| SVA assertion properties | 36 |
| SVA cover properties | 14 |
| Functional covergroups | 4 |
| Functional coverpoints | 32 |
| Functional crosses | 12 |

The functional coverage totals include one generic CSR/access covergroup and
three IBI covergroups. The IBI model contains 29 coverpoints and 11 crosses:

- `cg_ibi_attempt`
- `cg_ibi_completion`
- `cg_ibi_queue_irq`
- `x_bcr_capability`, `x_arb`, `x_entry`, `x_content`, `x_response`,
  `x_policy`, `x_error_status`, `x_error_recovery`, `x_master`, `x_queue`,
  and `x_interrupt`

Coverage implementation is not the same as coverage closure. Controller
policy, multi-target, timing-context, Controller FIFO-depth, and Target FIFO
depth still require qualification or additional closure evidence.

### 1.4 Current Tests

| Role | Test | Main intent |
|---|---|---|
| CSR | `smc_i3c_csr_smoke_test` | Basic AXI/RAL access and core identity |
| CSR | `smc_i3c_sanity_test` | Basic environment and DUT sanity |
| CSR | `smc_i3c_ral_all_regs_test` | RAL traversal of implemented registers |
| Target-TX | `smc_i3c_ibi_basic_test` | One MDB-only IBI, Controller VIP ACK |
| Target-TX | `smc_i3c_ibi_ack_nack_test` | ACK and NACK response behavior |
| Target-TX | `smc_i3c_ibi_mdb_payload_test` | MDB and payload transfer/content |
| Target-TX | `smc_i3c_ibi_fifo_irq_test` | IBI queue, threshold, drain, and IRQ behavior |
| Controller-RX | `smc_i3c_ibi_controller_receive_test` | Basic Target-initiated IBI receive |
| Controller-RX | `smc_i3c_ibi_controller_content_test` | MDB and payload receive/content |
| Controller-RX | `smc_i3c_ibi_controller_timing_context_test` | IBI in idle and post-transfer timing contexts |
| Controller-RX | `smc_i3c_ibi_controller_policy_test` | DAT accept/reject and payload policy |
| Controller-RX | `smc_i3c_ibi_controller_multi_target_test` | Multiple Target request/arbitration behavior |

### 1.5 Known Failures and Incomplete Closure

The package intentionally does not change checker expectations to hide DUT
behavior.

| Test or area | Current status |
|---|---|
| `smc_i3c_ibi_controller_policy_test` | RTL defect-reproduction test; DAT no-match behavior remains under design review and may report a real mismatch |
| `smc_i3c_ibi_controller_multi_target_test` | RTL defect-reproduction/closure test; multi-target behavior is not signoff-complete |
| Controller timing context and FIFO depth | Implemented framework exists, but closure is not signoff-complete |
| Target FIFO depth | Limited by the observable host-VIP service window; depth results require waveform review |


## 2. First-Time Setup

### 2.1 Requirements

- Linux shell with Bash, GNU Make, `awk`, `find`, and standard Unix tools.
- Synopsys VCS 2020.12 or newer. Record the exact qualified release.
- A recursive TT I3C checkout containing `src/i3c.f`.
- Caliptra RTL, normally under
  `$I3C_ROOT_DIR/third_party/caliptra-rtl`.
- Verdi and its VCS PLI only for FSDB generation or Verdi viewing.
- Slurm only when the Slurm backend is selected.
- A valid simulator/license environment supplied by the user's site.

UVM 2020.3.1 is bundled in `third_party/uvm-core-2020.3.1`. An external
compatible UVM can be selected with `DV_UVM_HOME`.

### 2.2 Obtain the External RTL

Clone the TT core recursively using the repository URL supplied by its owner:

```bash
git clone --recursive <TT_I3C_REPOSITORY_URL> /path/to/tt-i3c-core
export I3C_ROOT_DIR=/path/to/tt-i3c-core
```

If the checkout already exists:

```bash
git -C "$I3C_ROOT_DIR" submodule sync --recursive
git -C "$I3C_ROOT_DIR" submodule update --init --recursive
```

The reproducible delivery baseline is stored in
`i3c/sim/project/i3c_source_pins.mk` and summarized in
`docs/SOURCE_BASELINE.md`. The current I3C pin is
`a6361105cd3432699da636f1f5e6f1eb4df09ed2`. Keep
`SOURCE_MODE=pinned` for qualification runs, use `SOURCE_MODE=latest` to
compare a checkout with `origin/tt/main`, and use `SOURCE_MODE=worktree` for an
explicitly reviewed modified core. Commit mismatch, missing Git metadata, and
dirty-source findings are warnings; missing required RTL/RAL source files are
still blocking errors.

### 2.3 Local VCS Setup

The TT I3C RTL is attached in `i3c/sim/project/i3c_inputs.mk` at line 25
through `-f ${I3C_ROOT_DIR}/src/i3c.f`. The RAL and include paths use the same
root, so do not replace only this filelist line.

Pass the root for one command without exporting it:

```bash
I3C_ROOT_DIR=/path/to/tt-i3c-core ./run.sh doctor
```

To set a package-local default instead, edit `I3C_ROOT_DIR ?=` at
`i3c/sim/mk/i3c.mk:6`. Environment variables remain preferable because they
keep machine-specific paths out of the delivery.

`SOURCE_MODE` defaults to `pinned` at `i3c/sim/mk/i3c.mk:4`. Select another
mode for one command without exporting it:

```bash
SOURCE_MODE=latest ./run.sh doctor
SOURCE_MODE=worktree ./run.sh comp --show-output
```

To change the package default instead, edit `SOURCE_MODE ?= pinned` at line 4.
The expected commit itself is recorded at
`i3c/sim/project/i3c_source_pins.mk:3`.

Use this mode on a machine where `vcs` runs directly:

```bash
cd /path/to/tt_uvm_i3c

# Site-specific examples only. Use the module names provided by your IT team.
module load vcs
module load verdi

export I3C_ROOT_DIR=/path/to/tt-i3c-core
export DV_DEFAULT_SCHEDULER=local
export DV_VIEW_SCHEDULER=local

source ./run.sh env
./run.sh generate
./run.sh doctor
./run.sh comp --show-output
```

After `DV_DEFAULT_SCHEDULER=local` is exported, commands do not need
`--scheduler local`.

`source ./run.sh env` exports the bundled UVM and dependency settings into the
current shell. The public runner also loads those defaults internally, so this
source step does not need to be repeated before every command in the same
terminal. `I3C_ROOT_DIR` must still be exported in each new shell unless it is
placed in the user's shell startup file.

### 2.4 Slurm Setup

Use this mode when simulation jobs must be submitted through `srun`:

```bash
cd /path/to/tt_uvm_i3c

module load vcs
module load verdi

export I3C_ROOT_DIR=/path/to/tt-i3c-core
export DV_DEFAULT_SCHEDULER=slurm
export DV_VIEW_SCHEDULER=slurm

# Set only when required by the local Slurm installation.
export RUNNER_SLURM_PARTITION=<partition-name>

source ./run.sh env
./run.sh generate
./run.sh doctor
./run.sh comp --show-output
```

The default scheduler is `auto`: it selects Slurm when `srun` is available and
otherwise selects local execution. Explicitly exporting `local` or `slurm` is
recommended for reproducible behavior. A one-off override is also supported:

```bash
./run.sh comp --scheduler local --show-output
./run.sh test -t smc_i3c_csr_smoke_test --scheduler slurm
```

### 2.5 Optional Environment Overrides

| Variable | Meaning |
|---|---|
| `I3C_ROOT_DIR` | Required TT I3C checkout |
| `CALIPTRA_ROOT` | Optional Caliptra override; normally inferred below the TT checkout |
| `DV_UVM_HOME` | Optional compatible UVM override |
| `SOURCE_MODE` | `pinned` for the recorded baseline, `latest` for `origin/tt/main`, `worktree` for reviewed development, or `snapshot` for a non-Git release tree |
| `I3C_SOURCE_LAYOUT` | Source-layout selection; default `auto` |
| `DV_DEFAULT_SCHEDULER` | `local`, `slurm`, or `auto` |
| `DV_VIEW_SCHEDULER` | Scheduler used to launch waveform viewers |
| `RUNNER_SLURM_PARTITION` | Optional site Slurm partition |

Example without an explicit scheduler option:

```bash
export I3C_ROOT_DIR=/path/to/tt-i3c-core
export CALIPTRA_ROOT="$I3C_ROOT_DIR/third_party/caliptra-rtl"
export DV_DEFAULT_SCHEDULER=local
export DV_VIEW_SCHEDULER=local
source ./run.sh env
```

### 2.6 What `doctor` Does

`./run.sh doctor` is a read-only preflight and input-generation check. It:

1. checks that no host-specific/OCAH runtime path leaked into the standalone
   package;
2. checks the selected UVM package;
3. validates `I3C_ROOT_DIR`, `src/i3c.f`, source layout, and recursive
   dependencies, then reports Git cleanliness and commit provenance as
   non-blocking warnings;
4. checks the Caliptra checkout;
5. checks that VCS is available and meets the minimum version;
6. regenerates normalized compile and test-plan inputs.

It does not edit RTL or silently move the external core to another revision.

Capture the complete report when asking for support:

```bash
./run.sh doctor 2>&1 | tee doctor.log
```

### 2.7 Common First-Run Errors

| Message or symptom | Cause | Action |
|---|---|---|
| `I3C_ROOT_DIR is not set` | External core was not selected | `export I3C_ROOT_DIR=/path/to/tt-i3c-core` |
| `Missing I3C filelist .../src/i3c.f` | Wrong root or incomplete checkout | Select the TT repository root and initialize submodules |
| `Missing Caliptra RTL` | Recursive dependency is absent | Run recursive submodule sync/update or set `CALIPTRA_ROOT` |
| `I3C commit mismatch` warning | Checkout differs from the delivery pin | Continue for development, select `SOURCE_MODE=latest/worktree`, or check out the recorded pin for qualification |
| `source is a plain directory or unreadable Git worktree` warning | Source files exist without usable Git metadata | Continue compiling, but record the supplied source archive/version manually |
| `source has local changes` warning | Tracked or untracked files differ from the recorded commit | Continue only after reviewing the differences; qualification results are not reproducible from the commit alone |
| `UVM package not found` | Bundled UVM is missing or override is wrong | Restore `third_party/uvm-core-2020.3.1` or set a valid `DV_UVM_HOME` |
| `VCS executable not found` | Tool environment is not loaded | Load the site VCS module/setup and verify `command -v vcs` |
| `VCS compiler not found` or path mismatch | Inconsistent `VCS_HOME` and `PATH` | Use one site-supported VCS setup; verify `which vcs` and `VCS_HOME` agree |
| VCS version is below 2020.12 | Unsupported compiler version | Select VCS 2020.12 or newer |
| Verdi cannot open display | Viewer launched without a usable X11 session | Use local viewing or a Slurm/X11 configuration supported by the site |
| FSDB task/PLI error | Verdi PLI is unavailable at compile time | Load Verdi before compiling and regenerate/recompile with FSDB enabled |
| `Standalone package boundary` error | A host-specific absolute path entered a package input | Replace it with a package-relative path or an exported dependency root |
| Missing/stale generated filelist | Inputs were not regenerated after a pull | Run `./run.sh generate`, then `./run.sh doctor` |

## 3. Quick Run Guide

Run all commands from the package root. Do not invoke an internal runner from
inside `i3c/`.

### 3.1 Compile

```bash
./run.sh comp --show-output
```

Compile with code/functional coverage instrumentation:

```bash
./run.sh comp --cov --show-output
```

The VCS compile defaults to four compiler processes. This accelerates code
generation; it does not make the serial handoff regression run four tests at
once.

### 3.2 Run One Test

Run and stream simulator output to the terminal:

```bash
./run.sh test -t smc_i3c_ibi_basic_test --show-output
```

Run with a selected seed:

```bash
./run.sh test -t smc_i3c_ibi_basic_test --seed 12345 --show-output
```

Without `--show-output`, the command still prints concise progress and the
final verdict. Full compile/simulation output remains in the run directory.

### 3.3 Waveform Dumps

A normal test does not generate a waveform. `--dump` is the FSDB shorthand:

```bash
./run.sh test -t smc_i3c_ibi_basic_test --dump --show-output
```

Equivalent explicit FSDB command:

```bash
./run.sh test -t smc_i3c_ibi_basic_test \
  --dump-format fsdb --show-output
```

Generate VCD instead:

```bash
./run.sh test -t smc_i3c_ibi_basic_test \
  --dump-format vcd --show-output
```

Supported dump formats are `none`, `fsdb`, `vcd`, and `vpd`. Dump
instrumentation is selected at compile time. When changing format, allow the
runner to compile a matching simulation image; do not reuse an incompatible
`simv`.

Regression dumps are also supported:

```bash
./run.sh regression --dump-format fsdb
```

This can consume substantial disk space because each test/seed case gets its
own dump.

### 3.4 Test Suites and Coverage

```bash
./run.sh list-tests
./run.sh smoke
./run.sh target
./run.sh controller
./run.sh regression
./run.sh coverage
```

Run ten randomized seeds per enabled test:

```bash
./run.sh regression --rand-num 10
./run.sh coverage --rand-num 10 --target 90
```

Merge latest-PASS VDBs from a coverage run:

```bash
./run.sh merge-cov --id <RUN_ID> --show-output
```

Known defect-reproduction tests remain visible as failures. A failed test is
not converted to PASS to improve a regression or coverage headline.

### 3.5 Output and Log Layout

All generated data is below `i3c/sim/out/`. A single-test run uses:

```text
i3c/sim/out/runs/<run-id>/
|-- run.meta
|-- compile.meta
|-- logs/compile/compile.log
|-- cases/<test>/seed_<seed>/attempt_001/ (main log in cases)
|   |-- command.sh
|   |-- logs/sim.log
|   |-- logs/sim.clean.log
|   |-- dumps/<test>_seed_<seed>_attempt_1.<format>
|   `-- coverage/<test>.vdb
`-- summary/
    |-- test.log
    |-- test.errors.log
    |-- failure_quick_links.log
    `-- artifacts.tsv
```

A regression inserts
`bursts/Bxxx/attempt_001/` before each case tree and adds regression summary
files.

| Artifact | Description |
|---|---|
| `run.meta` | Run identity, command, project, and execution metadata |
| `compile.meta` | Compile top, filelist, work directory, debug database, and source revision |
| `manifest.tsv` | Planned test/seed cases |
| `logs/compile/compile.log` | Complete VCS compile log |
| `command.sh` | Exact simulator command for the case |
| `logs/sim.log` | Raw simulator output |
| `logs/sim.clean.log` | Normalized simulator log used for convenient review |
| `dumps/*.fsdb`, `*.vcd`, `*.vpd` | Optional per-case waveform |
| `coverage/*.vdb` | Per-case VCS coverage database |
| `summary/test.log` | Single-test summary |
| `summary/test.errors.log` | Single-test error extraction |
| `summary/regression.log` | Regression summary |
| `summary/regression.errors.log` | Regression error extraction |
| `summary/failure_quick_links.log` | Short paths to failed case logs |
| `summary/artifacts.tsv` | Machine-readable artifact index |
| `summary/*.latest.tsv` | Latest-attempt test/seed status tables |

Inspect the latest summary:

```bash
./run.sh summary
./run.sh summary --id <RUN_ID> --tail 200
./run.sh summary --id <RUN_ID> --show
```

### 3.6 Find and Open Waves

Always list artifacts first when the exact run path is unknown:

```bash
./run.sh view
./run.sh view --any-dump --limit 20
```

Open the latest FSDB:

```bash
./run.sh view --open --last --fsdb
```

Open a specific test/seed:

```bash
./run.sh view --open --last \
  --test smc_i3c_ibi_basic_test --seed 1 --fsdb
```

Inspect the matching simulation or compile log:

```bash
./run.sh view --log --last \
  --test smc_i3c_ibi_basic_test --seed 1 --tail 120
./run.sh view --compile --last --show-compile
```

Important `view` options:

| Group | Options |
|---|---|
| Select | `--dump`, `--log`, `--compile`, `--file`, `--last` |
| Filter | `--test`, `--seed`, `--format`, `--fsdb`, `--vcd`, `--vpd`, `--limit` |
| Action | `--open`, `--tail`, `--show-log`, `--show-compile`, `--open-log`, `--open-compile` |
| Viewer | `--viewer`, `--source-map auto|off|reparse`, `--scheduler`, `--cpus`, `--x11` |

Source-map modes:

- `auto`: use the saved Verdi debug database when valid; otherwise reparse the
  recorded filelist when possible.
- `off`: open only the waveform without source-code mapping.
- `reparse`: require Verdi to parse the recorded/current filelist and top.

For local GUI viewing without writing `--scheduler local` each time:

```bash
export DV_VIEW_SCHEDULER=local
./run.sh view --open --last --fsdb
```

## 4. Runner Script Inventory

The public API is only `./run.sh`. Files below
`i3c/sim/vcs_run_script/` are implementation modules and normally should not
be executed directly.

| Path | Purpose |
|---|---|
| `run.sh` | Public package entry point and hierarchical help |
| `i3c/sim/dv_project.sh` | Project name, top, filelist, tool, source pins, SVA policy, and defaults |
| `i3c/sim/project/generate_dv_inputs.sh` | Generates normalized VCS filelist and test plan |
| `i3c/sim/project/i3c_inputs.mk` | Ordered source emission for generated `compile.f` |
| `i3c/sim/project/i3c_source_pins.mk` | Machine-readable TT I3C and Caliptra baseline pins |
| `i3c/sim/vcs_run_script/check_config.sh` | Generic runner/project configuration checks |
| `i3c/sim/vcs_run_script/check_i3c_source.sh` | External TT/Caliptra source, state, and pin checks |
| `i3c/sim/vcs_run_script/check_standalone.sh` | Detects forbidden host-specific paths and package-boundary leaks |
| `i3c/sim/vcs_run_script/check_vcs_version.sh` | VCS availability and minimum-version check |
| `i3c/sim/vcs_run_script/clean.sh` | Scoped cleanup for run, log, dump, coverage, and temporary data |
| `i3c/sim/vcs_run_script/common.sh` | Shared paths, validation, locking, and utility functions |
| `i3c/sim/vcs_run_script/common_active_jobs.sh` | Active-job bookkeeping |
| `i3c/sim/vcs_run_script/common_attempt_retry.sh` | Attempt/seed retry policy and status |
| `i3c/sim/vcs_run_script/common_live_output.sh` | Concise live progress and heartbeat formatting |
| `i3c/sim/vcs_run_script/common_reporting.sh` | Verdict parsing, summaries, errors, and artifact indexing |
| `i3c/sim/vcs_run_script/common_scheduler.sh` | Local and Slurm command construction |
| `i3c/sim/vcs_run_script/cov_setup.cfg` | VCS coverage configuration |
| `i3c/sim/vcs_run_script/gen_mk_files.sh` | Regenerates project make fragments and test list |
| `i3c/sim/vcs_run_script/merge_cov.sh` | Selects and merges VDBs, then creates coverage reports |
| `i3c/sim/vcs_run_script/open_wave.sh` | Finds waves/logs and launches Verdi or another viewer |
| `i3c/sim/vcs_run_script/project_config.sh` | Loads and validates the project contract |
| `i3c/sim/vcs_run_script/run_compile.sh` | Creates and runs an isolated compile job |
| `i3c/sim/vcs_run_script/run_coverage.sh` | Coverage regression and closure orchestration |
| `i3c/sim/vcs_run_script/run_dispatch.sh` | Serial case dispatch and progress reporting |
| `i3c/sim/vcs_run_script/run_regression.sh` | Test-plan selection and regression orchestration |
| `i3c/sim/vcs_run_script/run_test.sh` | Single-test orchestration |
| `i3c/sim/vcs_run_script/runner_make.sh` | Controlled interface to project Make targets |
| `i3c/sim/vcs_run_script/summary.sh` | Displays stored run summaries and metadata |
| `i3c/sim/vcs_run_script/tt_local_env.sh` | Standalone UVM/core environment defaults |
| `i3c/sim/vcs_run_script/vcs_backend.mk` | VCS compile, elaborate, simulation, dump, and coverage backend |

Build inputs consumed by those scripts:

| Path | Purpose |
|---|---|
| `i3c/sim/Makefile` | Project make entry point |
| `i3c/sim/filelists/rtl.f` | RTL integration filelist |
| `i3c/sim/filelists/rtl_i3c.f` | TT I3C RTL selection filelist |
| `i3c/sim/filelists/test.f` | Human-readable test groups and enable state |
| `i3c/sim/mk/paths.mk` | Project path definitions |
| `i3c/sim/mk/incdirs.mk` | Include-directory definitions |
| `i3c/sim/mk/srcs.mk` | Ordered testbench source lists |
| `i3c/sim/mk/i3c.mk` | I3C-specific source and define integration |
| `i3c/sim/mk/i3c_child_srcs.mk` | Portable child-environment sources |

## 5. VNCHIP File Inventory

This section lists maintained VNCHIP verification and integration files. It
does not claim VNCHIP authorship for the external TT RTL, Caliptra RTL, bundled
UVM library, or inherited I3C VIP. Empty `.gitkeep` placeholders and generated
`i3c/sim/generated/` or `i3c/sim/out/` artifacts are intentionally omitted.
Per-file SPDX headers and `NOTICE` remain authoritative.

### 5.1 Package, Documentation, and DUT Integration

| Path | Description |
|---|---|
| `LICENSE` | Package Apache-2.0 license |
| `NOTICE` | Package attribution and provenance notices |
| `README.md` | Main setup, execution, and inventory guide |
| `docs/ARCHITECTURE.md` | Target-TX/Controller-RX topology and boundaries |
| `docs/KNOWN_ISSUES.md` | Known DUT, closure, and qualification limitations |
| `docs/SOURCE_BASELINE.md` | Extraction baseline, source pins, and UVM baseline |
| `i3c/README.md` | Compact project execution contract |
| `i3c/rtl/external/i3c_core.f` | External TT I3C filelist bridge |
| `i3c/rtl/external/i3c_manifest.mk` | External source-layout manifest |
| `i3c/rtl/smc_peripherals_stub.sv` | Stub DUT for non-RTL infrastructure checks |
| `i3c/rtl/smc_peripherals_top.sv` | I3C DUT integration top |
| `i3c/rtl/wrappers/smc_i3c_axi_adapter.sv` | AXI4-Lite to TT I3C integration adapter |
| `i3c/rtl/wrappers/smc_i3c_wrapper.sv` | TT I3C wrapper and boundary mapping |
| `i3c/verify/tb/smc_peripherals_tb.mk` | Testbench compile integration |

### 5.2 Portable Child Environment

| Path | Description |
|---|---|
| `i3c/verify/tb/children/i3c/blackbox/i3c_child_vseq_pkg.sv` | Portable child virtual-sequence package |
| `i3c/verify/tb/children/i3c/env/analysis/smc_i3c_boundary_item.sv` | Boundary transaction item |
| `i3c/verify/tb/children/i3c/env/apis/smc_i3c_csr_api.sv` | Abstract CSR API |
| `i3c/verify/tb/children/i3c/env/core/smc_i3c_child_context.sv` | Child runtime context |
| `i3c/verify/tb/children/i3c/env/services/smc_i3c_child_services.sv` | Child service interface |
| `i3c/verify/tb/children/i3c/env/smc_i3c_child_pkg.sv` | Child environment package |
| `i3c/verify/tb/children/i3c/env/utils/smc_i3c_child_constants.sv` | Child environment constants |
| `i3c/verify/tb/children/i3c/vseq/core/smc_i3c_child_base_vseq.sv` | Portable child base virtual sequence |
| `i3c/verify/tb/children/i3c/vseq/integration/portable/smc_i3c_child_csr_smoke_vseq.sv` | Portable child CSR smoke sequence |

### 5.3 Environment, Helpers, and Checking

| Path | Description |
|---|---|
| `i3c/verify/tb/env/smc_peripherals_env_pkg.sv` | Main UVM environment package |
| `i3c/verify/tb/env/ip/smc_peripherals_env.sv` | Top-level UVM environment |
| `i3c/verify/tb/env/ip/smc_peripherals_env_cfg.sv` | Environment configuration |
| `i3c/verify/tb/env/ip/smc_i3c_host_driver.sv` | I3C Controller-side integration driver |
| `i3c/verify/tb/env/ip/smc_i3c_target_driver.sv` | I3C Target-side integration driver |
| `i3c/verify/tb/env/ip/smc_i3c_monitor.sv` | I3C integration monitor |
| `i3c/verify/tb/env/core/smc_peripherals_vseq_context.sv` | Shared virtual-sequence runtime context |
| `i3c/verify/tb/env/services/smc_peripherals_vseq_services.sv` | Virtual-sequence runtime services |
| `i3c/verify/tb/env/helpers/smc_i3c_csr_access_seq.sv` | CSR frontdoor access sequence |
| `i3c/verify/tb/env/helpers/smc_i3c_csr_helper.sv` | Common I3C CSR helper API |
| `i3c/verify/tb/env/helpers/smc_i3c_controller_hci_helper.sv` | Controller HCI helper API |
| `i3c/verify/tb/env/analysis/smc_i3c_csr_scoreboard_cfg.sv` | CSR scoreboard configuration |
| `i3c/verify/tb/env/analysis/smc_i3c_ibi_transaction.sv` | IBI transaction models |
| `i3c/verify/tb/env/analysis/smc_i3c_ibi_observer.sv` | Target-TX passive observer |
| `i3c/verify/tb/env/analysis/smc_i3c_ibi_predictor.sv` | Target-TX reference predictor |
| `i3c/verify/tb/env/analysis/smc_i3c_ibi_scoreboard.sv` | Target-TX scoreboard |
| `i3c/verify/tb/env/analysis/smc_i3c_ibi_controller_observer.sv` | Controller-RX passive observer |
| `i3c/verify/tb/env/analysis/smc_i3c_ibi_controller_predictor.sv` | Controller-RX reference predictor |
| `i3c/verify/tb/env/analysis/smc_i3c_ibi_controller_scoreboard.sv` | Controller-RX scoreboard |
| `i3c/verify/tb/env/analysis/smc_i3c_ibi_sva_probe.sv` | UVM event to SVA probe bridge |
| `i3c/verify/tb/env/analysis/smc_peripherals_scoreboard.sv` | Shared CSR/access scoreboard |

### 5.4 RAL, Top, and Interfaces

| Path | Description |
|---|---|
| `i3c/verify/tb/ral/axi4lite_reg_adapter.sv` | UVM RAL to AXI4-Lite adapter |
| `i3c/verify/tb/ral/smc_i3c_ral_model.sv` | I3C RAL wrapper |
| `i3c/verify/tb/ral/smc_peripherals_ral_pkg.sv` | RAL package |
| `i3c/verify/tb/top/smc_peripherals_report_pkg.sv` | UVM report formatting |
| `i3c/verify/tb/top/smc_peripherals_tb_params_pkg.sv` | Testbench parameters |
| `i3c/verify/tb/top/tb_smc_peripherals_top.sv` | UVM testbench top |
| `i3c/verify/vip/smc_peripherals_vip/if/smc_peripherals_if.sv` | DUT/TB integration interface |

### 5.5 AXI4-Lite VIP

| Path | Description |
|---|---|
| `i3c/verify/vip/axi4lite_vip/axi4lite_vip_pkg.sv` | AXI4-Lite VIP package |
| `i3c/verify/vip/axi4lite_vip/axi4lite_vip.mk` | AXI4-Lite VIP compile integration |
| `i3c/verify/vip/axi4lite_vip/agent/axi4lite_agent.sv` | Active/passive AXI4-Lite agent |
| `i3c/verify/vip/axi4lite_vip/agent/axi4lite_driver.sv` | AXI4-Lite master driver |
| `i3c/verify/vip/axi4lite_vip/agent/axi4lite_monitor.sv` | AXI4-Lite passive monitor |
| `i3c/verify/vip/axi4lite_vip/agent/axi4lite_sequencer.sv` | AXI4-Lite sequencer |
| `i3c/verify/vip/axi4lite_vip/core/axi4lite_config.sv` | AXI4-Lite VIP configuration |
| `i3c/verify/vip/axi4lite_vip/core/axi4lite_item.sv` | AXI4-Lite transaction item |
| `i3c/verify/vip/axi4lite_vip/if/axi4lite_if.sv` | AXI4-Lite signal interface |
| `i3c/verify/vip/axi4lite_vip/sequences/axi4lite_base_seq.sv` | AXI4-Lite base read/write sequence |

### 5.6 Functional Coverage

| Path | Description |
|---|---|
| `i3c/verify/tb/coverage/smc_i3c_coverage_pkg.sv` | Coverage package and generic CSR/access coverage |
| `i3c/verify/tb/coverage/smc_i3c_ibi_item.sv` | Normalized IBI coverage item |
| `i3c/verify/tb/coverage/integration/smc_i3c_ibi_coverage.sv` | Integrated IBI coverage subscriber |
| `i3c/verify/tb/coverage/internal/smc_i3c_ibi_attempt_coverage.sv` | IBI capability, entry, and arbitration coverage |
| `i3c/verify/tb/coverage/internal/smc_i3c_ibi_completion_coverage.sv` | Response, content, policy, and recovery coverage |
| `i3c/verify/tb/coverage/ip/smc_i3c_ibi_queue_irq_coverage.sv` | FIFO, queue, status, and IRQ coverage |

### 5.7 Assertions

| Path | Description |
|---|---|
| `i3c/verify/tb/sva/integration/smc_i3c_boundary_sva.sv` | AXI boundary stability and denied-access assertions |
| `i3c/verify/tb/sva/integration/smc_i3c_ibi_bus_sva.sv` | Common IBI bus integrity/liveness assertions |
| `i3c/verify/tb/sva/integration/smc_i3c_ibi_target_sva.sv` | DUT-Target IBI assertions |
| `i3c/verify/tb/sva/integration/smc_i3c_ibi_controller_sva.sv` | DUT-Controller IBI assertions |
| `i3c/verify/tb/sva/integration/smc_i3c_ibi_protocol_sva.sv` | Normalized transaction-level IBI protocol assertions |
| `i3c/verify/tb/sva/waivers/global_waivers.list` | Global reviewed SVA waiver keys |
| `i3c/verify/tb/sva/waivers/policies/functional.list` | Functional-suite SVA waiver keys |
| `i3c/verify/tb/sva/waivers/suite_policies.tsv` | Test-to-SVA-policy mapping |

### 5.8 Test Classes

Base classes are listed first and are not standalone test objectives.

| Path | Description |
|---|---|
| `i3c/verify/tb/tests/core/base/smc_peripherals_base_test.sv` | Shared UVM base test |
| `i3c/verify/tb/tests/ip_only/i3c/ibi/smc_i3c_ibi_base_test.sv` | Shared IBI base test and role configuration |
| `i3c/verify/tb/tests/smc_peripherals_test_pkg.sv` | Test package and compile order |
| `i3c/verify/tb/tests/ip_only/i3c/smc_i3c_csr_smoke_test.sv` | CSR smoke test |
| `i3c/verify/tb/tests/ip_only/i3c/smc_i3c_sanity_test.sv` | Sanity test |
| `i3c/verify/tb/tests/ip_only/i3c/smc_i3c_ral_all_regs_test.sv` | All-register RAL test |
| `i3c/verify/tb/tests/ip_only/i3c/ibi/smc_i3c_ibi_basic_test.sv` | Basic Target-TX IBI test |
| `i3c/verify/tb/tests/ip_only/i3c/ibi/smc_i3c_ibi_ack_nack_test.sv` | Target-TX ACK/NACK test |
| `i3c/verify/tb/tests/ip_only/i3c/ibi/smc_i3c_ibi_mdb_payload_test.sv` | Target-TX MDB/payload test |
| `i3c/verify/tb/tests/ip_only/i3c/ibi/smc_i3c_ibi_fifo_irq_test.sv` | Target-TX FIFO/IRQ test |
| `i3c/verify/tb/tests/ip_only/i3c/ibi/smc_i3c_ibi_controller_receive_test.sv` | Basic Controller-RX IBI test |
| `i3c/verify/tb/tests/ip_only/i3c/ibi/smc_i3c_ibi_controller_content_test.sv` | Controller-RX content test |
| `i3c/verify/tb/tests/ip_only/i3c/ibi/smc_i3c_ibi_controller_timing_context_test.sv` | Controller-RX timing-context test |
| `i3c/verify/tb/tests/ip_only/i3c/ibi/smc_i3c_ibi_controller_policy_test.sv` | Controller-RX policy defect-reproduction test |
| `i3c/verify/tb/tests/ip_only/i3c/ibi/smc_i3c_ibi_controller_multi_target_test.sv` | Controller-RX multi-target defect/closure test |

### 5.9 Sequences and Virtual Sequences

| Path | Description |
|---|---|
| `i3c/verify/tb/vseq/smc_peripherals_vseq_pkg.sv` | Virtual-sequence package and compile order |
| `i3c/verify/tb/vseq/core/base/smc_peripherals_base_vseq.sv` | Shared base virtual sequence |
| `i3c/verify/tb/vseq/ip_only/i3c/smc_i3c_csr_smoke_seq.sv` | CSR access sequence |
| `i3c/verify/tb/vseq/ip_only/i3c/smc_i3c_csr_smoke_vseq.sv` | CSR smoke virtual sequence |
| `i3c/verify/tb/vseq/ip_only/i3c/smc_i3c_sanity_vseq.sv` | Sanity virtual sequence |
| `i3c/verify/tb/vseq/ip_only/i3c/smc_i3c_ral_all_regs_vseq.sv` | All-register RAL virtual sequence |
| `i3c/verify/tb/vseq/ip_only/i3c/ibi/smc_i3c_ibi_base_vseq.sv` | Shared IBI setup, RAL, timeout, and check helpers |
| `i3c/verify/tb/vseq/ip_only/i3c/ibi/smc_i3c_host_accept_ibi_seq.sv` | Controller VIP sequence that ACKs/NACKs DUT Target IBI |
| `i3c/verify/tb/vseq/ip_only/i3c/ibi/smc_i3c_target_send_ibi_seq.sv` | Target VIP sequence that initiates IBI toward DUT Controller |
| `i3c/verify/tb/vseq/ip_only/i3c/ibi/smc_i3c_target_private_write_seq.sv` | Target VIP private-write sequence |
| `i3c/verify/tb/vseq/ip_only/i3c/ibi/smc_i3c_ibi_basic_vseq.sv` | Basic Target-TX IBI virtual sequence |
| `i3c/verify/tb/vseq/ip_only/i3c/ibi/smc_i3c_ibi_ack_nack_vseq.sv` | Target-TX ACK/NACK virtual sequence |
| `i3c/verify/tb/vseq/ip_only/i3c/ibi/smc_i3c_ibi_mdb_payload_vseq.sv` | Target-TX MDB/payload virtual sequence |
| `i3c/verify/tb/vseq/ip_only/i3c/ibi/smc_i3c_ibi_fifo_irq_vseq.sv` | Target-TX FIFO/IRQ virtual sequence |
| `i3c/verify/tb/vseq/ip_only/i3c/ibi/smc_i3c_ibi_controller_receive_vseq.sv` | Basic Controller-RX IBI virtual sequence |
| `i3c/verify/tb/vseq/ip_only/i3c/ibi/smc_i3c_ibi_controller_content_vseq.sv` | Controller-RX content virtual sequence |
| `i3c/verify/tb/vseq/ip_only/i3c/ibi/smc_i3c_ibi_controller_timing_context_vseq.sv` | Controller-RX timing-context virtual sequence |
| `i3c/verify/tb/vseq/ip_only/i3c/ibi/smc_i3c_ibi_controller_policy_vseq.sv` | Controller-RX DAT/payload-policy virtual sequence |
| `i3c/verify/tb/vseq/ip_only/i3c/ibi/smc_i3c_ibi_controller_multi_target_vseq.sv` | Controller-RX multi-target virtual sequence |

## 6. Using Another Runner or Simulator

This section has two layers:

1. **Tool-independent requirements** define the behavior needed for an
   equivalent verification flow.
2. **VCS/Verdi reference implementation** documents how the supplied scripts
   currently implement that behavior.

The receiving team may use Make, Python, Tcl, CI, a simulator-native
regression manager, or another internal system. It does not need to retain
`run.sh`, Slurm, the current directory layout, VCS databases, or the current
report format.

### 6.1 Requirement Keywords

The keywords below are normative in this section:

- **MUST:** required for equivalent behavior.
- **MUST NOT:** prohibited because it can produce an incorrect verification
  result.
- **SHOULD:** recommended; another implementation is acceptable when the
  difference is documented.
- **MAY:** optional.

These requirements apply to verification behavior and evidence, not to script
names, implementation language, file layout, scheduler, or simulator choice.

### 6.2 Tool-Independent Requirements

#### Required and Optional Components

The following components are required for RTL verification:

| Component | Requirement |
|---|---|
| TT I3C RTL and recursive Caliptra dependency | **MUST** be available at a known revision |
| AXI4-Lite VIP | **MUST** provide DUT CSR/HCI frontdoor access |
| I3C VIP | **MUST** support the Controller and Target roles required by the selected tests |
| DUT wrapper and integration interface | **MUST** connect AXI, I3C SDA/SCL, reset, clock, IRQ, and required status signals |
| UVM environment, RAL, tests, and sequences | **MUST** be compiled for the implemented test suite |
| Predictors and scoreboards | **MUST** be enabled for tests that depend on their checks |
| SVA | **MUST** be enabled for a qualification run |
| Functional coverage collectors | **MUST** be enabled for a coverage run |
| Code coverage | **SHOULD** be enabled for a coverage run when supported |
| Waveform dump | **MAY** be disabled for normal regression and **SHOULD** be enabled for debug/reproduction |
| Slurm, parallel execution, retry, HTML reports, and Verdi | **MAY** be replaced or omitted |

The source files may be reorganized. Their include relationships, package
dependencies, and effective compilation order **MUST** remain valid.

#### Required Inputs

A compile operation **MUST** receive or resolve:

| Input | Meaning |
|---|---|
| RTL revision | TT I3C revision and recursive dependency revisions |
| Source set and order | UVM, VIP, RAL, coverage, SVA, wrapper, top, and RTL compilation order |
| Top | `tb_smc_peripherals_top`, unless an equivalent integration top is intentionally provided |
| Defines | `SMC_USE_I3C_RTL`, `SMC_USE_I3C_RAL`, and `UVM_REG_DATA_WIDTH=128` or equivalent configuration |
| UVM implementation | UVM 2020.3.1 or a qualified compatible implementation |
| Coverage mode | Disabled, functional only, or functional plus supported code metrics |
| Dump mode | Disabled or a supported waveform format |

A test operation **MUST** receive or resolve:

| Input | Meaning |
|---|---|
| Test class | UVM test to execute |
| Seed | Reproducible random seed |
| Plusargs/configuration | Test-specific controls such as `+IBI_REQUIRE_COV` |
| DUT role/profile | Target-TX or Controller-RX configuration required by the test |
| Timeout | Finite test or infrastructure timeout |

The input representation **MAY** be a file, command line, database, CI
configuration, or simulator-native test definition.

#### Required Outputs

Each compile **MUST** produce:

- a compile/elaboration verdict;
- a complete compile log;
- the selected RTL revision, tool/version, top, and effective source/config
  information needed to reproduce the build.

Each test/seed case **MUST** produce the following logical result fields. The
physical format is implementation-defined.

| Field | Required content |
|---|---|
| Test | UVM test class |
| Seed | Random seed used by the simulator |
| Attempt | Attempt identifier when retry is used; otherwise a fixed value is acceptable |
| Status | `PASS`, `COMPILE_FAIL`, `INFRA_FAIL`, or `VERIFICATION_FAIL` |
| Failure evidence | Failure category and concise reason when status is not `PASS` |
| Simulator status | Process/exit result |
| Log reference | Location or identifier of the complete simulation log |
| Source/tool identity | RTL revision and simulator/version, directly or through the compile record |
| Dump reference | Waveform location when dump was requested |
| Coverage reference | Coverage database/report identity when coverage was requested |

A regression **MUST** retain a result for every planned test/seed case and
**MUST** identify cases that were not executed.

#### Equivalence Criteria

A replacement flow is equivalent for a test when all of the following hold:

1. It compiles the same effective DUT and verification source set with
   equivalent defines and configuration.
2. It runs the same UVM test, seed, test plusargs, and DUT role/profile.
3. The driver, monitor, predictor, scoreboard, SVA, and coverage components
   required by that test are active.
4. It observes and classifies all failure sources listed below.
5. It produces enough log and revision information to reproduce the result.
6. When dump or coverage is requested, it produces usable corresponding
   evidence.

Identical filenames, command lines, output directories, database formats, and
console text are **NOT** required.

#### Pass and Failure Classification

A case **MUST NOT** be reported as `PASS` when any of these conditions is
present:

- compile or elaboration failure;
- non-zero simulator exit status, unless the flow proves it is an explicitly
  handled tool convention and no failure occurred;
- `UVM_ERROR` or `UVM_FATAL`;
- plain SystemVerilog `$error` or `$fatal`;
- SVA failure, including the normalized `SVA: ap_name` marker;
- scoreboard mismatch;
- protocol/test timeout;
- missing expected completion or required output;
- corrupted, truncated, or missing simulation result.

Failures **MUST** be classified as follows:

| Class | Definition | Examples |
|---|---|---|
| `COMPILE_FAIL` | Source compilation or elaboration did not produce a runnable image | Syntax error, missing package/module, unresolved top, elaboration error |
| `INFRA_FAIL` | The verification case did not complete because the execution environment failed | Missing license/tool, scheduler/node failure, inaccessible filesystem, process killed by infrastructure |
| `VERIFICATION_FAIL` | Simulation ran far enough to detect incorrect DUT, TB, or protocol behavior | UVM error/fatal, SVA failure, scoreboard mismatch, functional timeout, unexpected response |
| `PASS` | Compile and simulation completed with no required failure evidence | All enabled checks completed without error |

A suspected RTL defect remains `VERIFICATION_FAIL` until triaged. The result
**MAY** add a secondary tag such as `DUT_MISMATCH`, `TB_ISSUE`, or
`NEEDS_REVIEW`, but it **MUST NOT** be changed to `PASS`.

Automatic retry **SHOULD** be limited to `INFRA_FAIL`. A
`VERIFICATION_FAIL` **MUST NOT** be repeatedly retried solely to obtain a
passing attempt. A later PASS **MUST NOT** erase the original failing result
or its evidence.

#### Coverage Requirements

A coverage run:

- **MUST** collect SystemVerilog functional covergroup coverage when the
  simulator supports the covergroup constructs used by this environment;
- **SHOULD** collect line, condition, branch, toggle, and FSM coverage when
  supported;
- **MUST** associate coverage evidence with identifiable test/seed results;
- **MUST** state whether failed-test coverage is included or excluded;
- **MUST NOT** silently include rejected, corrupted, or incompatible
  databases in a successful merge;
- **MUST** report the status of each requested metric as `AVAILABLE`,
  `UNSUPPORTED`, `NOT_COLLECTED`, or `FAILED`.

If a simulator does not support a requested code-coverage metric, the metric
**MUST** be reported as `UNSUPPORTED`. It **MUST NOT** be represented as 0%,
100%, or silently removed from the requested metric list.

An unsupported optional code metric does not by itself invalidate functional
test equivalence. It does mean that the new flow is not coverage-equivalent
for that metric. If functional covergroup coverage is unsupported, the flow
may still be used for functional execution, but it **MUST NOT** claim
functional-coverage equivalence.

#### Waveform and Debug Requirements

Waveform generation is optional for an ordinary regression. When requested:

- the flow **MUST** report whether dump creation succeeded;
- the waveform **SHOULD** include DUT hierarchy, AXI4-Lite activity, SDA/SCL,
  IRQ, reset/clock, and relevant testbench transaction/probe signals;
- the waveform format **MAY** be FSDB, VCD, VPD, SHM, WLF, or another usable
  native format;
- source mapping **SHOULD** be available when supported by the selected
  viewer.

Failure to create a requested dump **MUST** be reported. It **SHOULD** be
classified as `INFRA_FAIL` when the dump is a required deliverable, or as a
separate artifact failure when the simulation verdict remains independently
valid.

### 6.3 Acceptance Tests for a Replacement Flow

The following checks provide objective evidence that a replacement flow is
implemented correctly:

| Check | Expected result |
|---|---|
| Compile the full RTL/UVM environment | Runnable simulation image or simulator-native equivalent |
| Run `smc_i3c_csr_smoke_test` with a fixed seed | CSR access and basic environment checks complete |
| Run `smc_i3c_ibi_basic_test` | DUT-Target/I3C-Controller path is operational |
| Run `smc_i3c_ibi_controller_receive_test` | DUT-Controller/I3C-Target path is operational |
| Inject or preserve a known `UVM_ERROR` | Case is `VERIFICATION_FAIL` |
| Inject or preserve an SVA failure | Case is `VERIFICATION_FAIL` and identifies the failed assertion |
| Inject or preserve a scoreboard mismatch | Case is `VERIFICATION_FAIL` |
| Simulate a missing license or killed worker | Case is `INFRA_FAIL`, not verification PASS/FAIL |
| Request a waveform | Dump status and usable waveform are produced |
| Run one coverage case | Functional coverage and supported code metrics are reported |
| Merge multiple coverage cases | Included/excluded cases and metric availability are visible |
| Run all 12 tests | Every planned test/seed has an explicit result |

The replacement flow **SHOULD** compare its 12-test results with a reference
VCS run using the same RTL revision, tests, seeds, and plusargs. Any difference
**MUST** be investigated before the new environment is declared qualified.

### 6.4 Current VCS/Verdi Reference Implementation

This subsection is descriptive, not normative. It records how the supplied
scripts currently satisfy the requirements above.

#### Current Script Responsibilities

| Script area | Current VCS flow behavior |
|---|---|
| Environment setup | Resolves the external TT core, Caliptra, bundled/overridden UVM, VCS, Verdi, and local/Slurm scheduler settings |
| `generate` | Produces an ordered VCS filelist and normalized test plan |
| `doctor` | Checks package boundaries, required source files, UVM, VCS version, and generated inputs; Git pin/dirty-state findings are warnings |
| Compile | Invokes VCS with SystemVerilog, UVM/DPI, DUT defines, top, filelist, optional coverage, and dump instrumentation |
| Single test | Selects UVM test, seed, plusargs, verbosity, dump, and coverage |
| Regression | Expands enabled tests/seeds, runs cases serially, retries infrastructure failures, and records case verdicts |
| Reporting | Parses process status, UVM, SystemVerilog, SVA, scoreboard, and timeout evidence |
| Coverage | Creates design/per-test VDBs, validates selected databases, merges with URG, and creates reports |
| Wave viewing | Finds FSDB/VCD/VPD artifacts and opens the selected viewer |
| Source mapping | Uses VCS KDB/Verdi debug data or reparses the recorded filelist/top |

The current source order can be inspected with:

```bash
export I3C_ROOT_DIR=/path/to/tt-i3c-core
./run.sh generate
cat i3c/sim/generated/compile.f
```

This generated file is only a convenient VCS-oriented representation. A
replacement flow does not need to generate or store a file named `compile.f`.

#### VCS Compile and Run

The current compile backend performs the equivalent of:

```text
vcs -full64 -j<N> -sverilog
    <UVM and optional UVM DPI sources>
    -f <ordered filelist>
    -top tb_smc_peripherals_top
    -o <simulation executable>
    <optional coverage options>
    <optional dump/debug options>
```

The current RTL build enables:

```text
SMC_USE_I3C_RTL
SMC_USE_I3C_RAL
UVM_REG_DATA_WIDTH=128
```

The current simulation selects the test and seed with:

```text
+UVM_TESTNAME=<test-class>
+ntb_random_seed=<seed>
```

Coverage-oriented IBI tests additionally use `+IBI_REQUIRE_COV`, as recorded
in the generated test plan.

#### VCS Coverage

VCS currently uses:

```text
-cm line+cond+fsm+tgl+branch
-cm_dir <case-or-design>.vdb
-cm_name <database-name>
```

The scripts create a design VDB and per-test VDBs. `urg` validates, merges, and
reports the selected databases. `.vdb` and `urg` are VCS implementation
details, not tool-independent requirements.

#### FSDB and Verdi

For FSDB, the current VCS flow uses integrated debug:

```text
-kdb -debug_access+all
```

or the legacy Verdi PLI integration:

```text
-P <FSDB_PLI_DIR>/novas.tab <FSDB_PLI_DIR>/pli.a
```

Runtime options select FSDB, VCD, or VPD and provide the output path to the
testbench. Verdi source mapping uses `simv.daidir`, or reparses the saved
filelist/top. VCD may be converted to an FSDB cache before Verdi opens it.

FSDB, KDB, `simv.daidir`, and Verdi are reference implementation details. A
replacement flow may use SHM, WLF, VCD, another FSDB integration, or a
simulator-native waveform/debug database.

#### VCS Diagnostics

The current VCS setup includes options such as:

```text
-q
-lca
-error=noIOPCWM
+lint=TFIPC-L
+vcs+lic+wait
-assert quiet
```

These options control VCS output, licensing, warning policy, and assertion
printing. They are not portable requirements. Another simulator should use
its corresponding diagnostics, license-wait, assertion, and verbosity
settings while satisfying the tool-independent pass/fail rules above.
