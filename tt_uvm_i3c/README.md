# I3C In-Band Interrupt (IBI) UVM Verification

## Overview

This package contains a standalone UVM environment for verification of the
I3C In-Band Interrupt (IBI) feature in DUT-Target transmit (Target-TX) and
DUT-Controller receive (Controller-RX) roles. It provides stimulus, protocol
VIP, AXI4-Lite register access, RAL integration, predictors, scoreboards, SVA,
functional coverage, and a verification plan.

The TT I3C DUT RTL and its recursive Caliptra dependency are maintained in
external repositories and are not distributed here. This handoff records the
external revisions required for reproducible candidate qualification. It does
not claim verification of the complete I3C protocol or complete DUT.

The bundled Bash runner reproduces the reference compile, test, regression,
waveform, and IBI coverage flows. It is optional automation and is not a
runtime dependency of the UVM environment. Users may integrate the documented
sources, tests, plusargs, and verdict criteria into their existing
orchestration framework.

## Verification Scope

### In Scope

- Target-TX IBI request, ACK/NACK response, payload, and mandatory data byte
  checking.
- Target retry, retry exhaustion, eligibility, busy-bus deferral, FIFO/IRQ
  effects, and recovery.
- Controller-RX IBI receipt, content/MDB decode, DAT and payload policy,
  response descriptors, queue/FIFO state, interrupt behavior, and reset/flush.
- IBI timing at idle, after normal transfer, and during activity that requires
  deferral.
- Multi-target/requester ordering, arbitration, DUT win/loss, queue pressure,
  and recovery.
- Directed, constrained-random, multi-seed, stress, and reset scenarios.
- Passive IBI protocol/role SVA and IBI-focused functional coverage mapped to
  the [Verification plan](docs/verification/VERIFICATION_PLAN.md).
- CSR/RAL smoke and sanity tests required to establish the IBI environment.

### Out of Scope

- Full I3C protocol and full-DUT verification.
- RTL code-coverage closure and unrelated AXI/CSR boundary coverage.
- Full generated-RAL verification.
- Features and simulator configurations listed in the authoritative known
  issues document.

## Repository Structure

```text
.
├── docs/                    # Central documentation, evidence, and provenance
├── i3c/
│   ├── rtl/                 # Local wrapper/adapter and external-core hook
│   ├── sim/                 # Reference VCS flow, test plan, and generated inputs
│   └── verify/              # UVM TB, RAL integration, SVA, coverage, and VIP
├── third_party/             # Bundled Accellera UVM 2020.3.1
├── run.sh                   # Optional reference-runner entry point
├── CHANGELOG.md
├── LICENSE
└── NOTICE
```

Generated build and run artifacts belong under `i3c/sim/out/` and are not
release sources.

## Architecture and DUT Integration

The environment contains AXI4-Lite and I3C stimulus paths, passive RAL
prediction, role-specific IBI scoreboards, SVA, and functional coverage. The
reference top is `tb_smc_peripherals_top`; the external DUT sources enter
through `${I3C_ROOT_DIR}/src/i3c.f`.

See [Architecture](docs/user-guide/ARCHITECTURE.md) for the UVM architecture,
DUT wrapper, interface connectivity, build guards, portable layer, and
integration details. Customer-specific wrapper mappings require separate
integration qualification when the delivered wrapper is not reused.

## Prerequisites and Dependencies

- Synopsys VCS; the reference runner declares minimum version `2020.12`.
- GNU Make, Bash, Git, and standard POSIX command-line utilities.
- Slurm is optional for scheduled execution.
- Verdi is optional for FSDB and interactive coverage viewing.
- Accellera UVM 2020.3.1 is bundled under
  `third_party/uvm-core-2020.3.1/`.
- AXI4-Lite and I3C VIP sources are delivered under `i3c/verify/vip/`.
- TT I3C and Caliptra RTL remain external.

| Variable | Purpose | Default/requirement |
|---|---|---|
| `I3C_ROOT_DIR` | External TT I3C checkout | Required for RTL mode |
| `CALIPTRA_ROOT` | Caliptra checkout | `${I3C_ROOT_DIR}/third_party/caliptra-rtl` when available |
| `SOURCE_MODE` | Source validation policy | `pinned` for qualification |
| `DV_UVM_HOME` | UVM source root | Bundled UVM 2020.3.1 |

See [Third-party software](docs/THIRD_PARTY.md) and
[Source baseline](docs/release/SOURCE_BASELINE.md).

## Quick Start

Run commands from the package root. Tool module names are installation
specific.

```bash
export I3C_ROOT_DIR=/path/to/tt-i3c-core
export CALIPTRA_ROOT=/path/to/caliptra-rtl
source ./run.sh env tt
./run.sh generate
./run.sh doctor --source-mode pinned
./run.sh compile --show-output
```

`CALIPTRA_ROOT` may be omitted when the required checkout is available at
`${I3C_ROOT_DIR}/third_party/caliptra-rtl`.

Run smoke and an IBI feature test:

```bash
./run.sh test -t smc_i3c_csr_smoke_test --show-output
./run.sh test -t smc_i3c_ibi_target_tx_basic_test --show-output
```

Run one planned case or the enabled regression:

```bash
./run.sh regression --case retry_one_short --show-output
./run.sh regression --all
```

## Tests

The delivered plan includes directed, constrained-random, multi-seed, stress,
recovery, reset, and multi-target IBI scenarios. List the authoritative tests,
cases, plusargs, and enable state with:

```bash
./run.sh list-tests --all
```

Test and coverage counts are authoritative only in
[Release manifest](docs/release/RELEASE_MANIFEST.md). Requirement-to-test and
coverage mappings are defined by the
[Verification plan](docs/verification/VERIFICATION_PLAN.md).

## Common Configuration

| Option | Purpose |
|---|---|
| `--seed N` / `--seeds LIST` | Reproduce or override simulation seeds |
| `--plusargs TEXT` | Add runtime plusargs to a single test |
| `--cov` | Enable coverage for compile/test |
| `--dump-format vcd\|vpd\|fsdb` | Select waveform output |
| `--scheduler local\|slurm\|auto` | Select execution backend |

See [Reference runner](docs/user-guide/REFERENCE_RUNNER.md) for regression,
randomization, parallelism, retry, coverage, and artifact options.

## Pass / Fail Criteria

A case is PASS only when simulation exits successfully, reaches a recognized
UVM completion summary, and no functional failure is found. An external runner
must enforce equivalent criteria. Failures include:

- nonzero `UVM_ERROR` or `UVM_FATAL` evidence;
- an unwaived SVA failure;
- a scoreboard mismatch or explicit functional failure;
- a timeout, tool crash, license/scheduler failure, or unrecovered nonzero
  execution result;
- missing required IBI coverage sampling for a qualifying entry.

UVM warnings are reported but do not alone define failure. Retry history is
retained, and only the final explicit PASS attempt is eligible for coverage
merge.

## Coverage

Qualification uses IBI assertion and functional-group coverage. RTL code
coverage is outside the current IBI qualification denominator. Coverage
scope and requirement mappings are defined in the
[Verification plan](docs/verification/VERIFICATION_PLAN.md); qualification
evidence is recorded in the
[Release manifest](docs/release/RELEASE_MANIFEST.md).

## Known Limitations

- This package verifies the documented IBI feature scope, not full I3C or
  full-DUT behavior.
- The reference flow targets VCS; other simulators are not qualified. This
  is independent from candidate release qualification, which remains
  pending (see [Qualification](docs/verification/QUALIFICATION.md)).
- Some RTL and RAL behaviors remain outside the current qualification scope.

See [Known issues](docs/verification/KNOWN_ISSUES.md) for the authoritative
issue list and disposition.

## Debugging

```bash
./run.sh summary
./run.sh summary --fail
./run.sh view --run-id <RUN_ID>
```

See [Reference runner](docs/user-guide/REFERENCE_RUNNER.md) for log, waveform,
retry, HTML summary, coverage, and artifact-navigation details.

## Handoff Baseline

```text
Status: Candidate — not yet qualified
Handoff date: 2026-08-20
TT I3C baseline: see docs/release/SOURCE_BASELINE.md
Qualification status: see docs/release/RELEASE_MANIFEST.md
UVM baseline: Accellera UVM 2020.3.1
```

Git commit or release tag is the package identity. Qualification requires
`SOURCE_MODE=pinned` and clean external checkouts.

## Documentation

See [docs/README.md](docs/README.md) for the complete documentation index.
Development history is recorded in [CHANGELOG.md](CHANGELOG.md).

## License / Notice

See [LICENSE](LICENSE) and [NOTICE](NOTICE) for licensing and attribution.
