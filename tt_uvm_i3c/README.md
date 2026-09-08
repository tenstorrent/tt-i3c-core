# I3C In-Band Interrupt (IBI) UVM Verification

## Overview

This package contains a standalone UVM environment for verification of the
I3C In-Band Interrupt (IBI) feature in DUT-Target transmit (Target-TX) and
DUT-Controller receive (Controller-RX) roles. It provides stimulus, protocol
VIP, AXI4-Lite register access, RAL integration, predictors, scoreboards, SVA,
functional coverage, and a verification plan.

The TT I3C DUT RTL is consumed from the containing repository; its recursive
Caliptra dependency is resolved from the configured dependency root and is not
distributed here. This handoff records the native and dependency revisions
required for reproducible candidate qualification. It does not claim
verification of the complete I3C protocol or complete DUT.

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
- Multi-target/requester ordering, arbitration, and DUT win/loss, plus
  canonical queue/FIFO/IRQ and recovery-cleanup scenarios.
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
│   ├── rtl/                 # Reserved for project-local RTL (native core is resolved from the containing repository)
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
reference top is `tb_i3c_top`; the native DUT sources enter through
`${I3C_ROOT_DIR}/src/i3c.f`.

See [Architecture](docs/user-guide/ARCHITECTURE.md) for the UVM architecture,
native wrapper, interface connectivity, and integration details.

## Prerequisites and Dependencies

- Synopsys VCS; the reference runner declares minimum version `2020.12`.
- GNU Make, Bash, Git, and standard POSIX command-line utilities.
- Slurm is optional for scheduled execution.
- Verdi is optional for FSDB and interactive coverage viewing.
- Accellera UVM 2020.3.1 is bundled under
  `third_party/uvm-core-2020.3.1/`.
- AXI4-Lite and I3C VIP sources are delivered under `i3c/verify/vip/`.
- TT I3C RTL is consumed from the containing repository; Caliptra RTL remains a
  documented dependency.

| Variable | Purpose | Default/requirement |
|---|---|---|
| `I3C_ROOT_DIR` | Optional native TT I3C root override | Auto-discovered by walking upward to a containing `src/i3c.f`; an override must contain `src/i3c.f` |
| `CALIPTRA_ROOT` | Caliptra checkout | `${I3C_ROOT_DIR}/third_party/caliptra-rtl` when available |
| `DV_UVM_HOME` | UVM source root | Bundled UVM 2020.3.1 |

See [Third-party software](docs/THIRD_PARTY.md) and
[Source baseline](docs/release/SOURCE_BASELINE.md).

## Quick Start

Run commands from the package root. Tool module names are installation
specific.

```bash
export CALIPTRA_ROOT=/path/to/caliptra-rtl
./run.sh generate
./run.sh doctor
./run.sh compile --show-output
```

The runner discovers `I3C_ROOT_DIR` from the containing repository. Set it only
when the package is being integrated from a workspace where the native source
root is not an ancestor. `CALIPTRA_ROOT` may be omitted when the required
dependency is available at `${I3C_ROOT_DIR}/third_party/caliptra-rtl`.

Run smoke and an IBI feature test:

```bash
./run.sh test -t i3c_csr_smoke_test --show-output
./run.sh test -t i3c_ibi_target_tx_basic_test --show-output
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

The eight historical customer scenario names remain in the plan as
compatibility identities. The retry-limit identity is explicitly single-
requester; the other multi-target identities delegate to canonical engines.
Their canonical engines and evidence sources are listed in Verification Plan
Section 5.0; a wrapper name alone is not an additional signoff claim.

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

## Historical Handoff Baseline

This is the 2026-08-20 handoff snapshot. It is retained for provenance and is
not the current candidate identity; see the [release manifest](docs/release/RELEASE_MANIFEST.md)
for the active branch, source HEAD, and qualification state.

```text
Status: Candidate — not yet qualified
Handoff date: 2026-08-20
TT I3C baseline: see docs/release/SOURCE_BASELINE.md
Qualification status: see docs/release/RELEASE_MANIFEST.md
UVM baseline: Accellera UVM 2020.3.1
```

Git commit or release tag is the package identity. Qualification requires the
native source root resolved by `I3C_ROOT_DIR` to be reviewed and clean.

## Documentation

See [docs/README.md](docs/README.md) for the complete documentation index.
Development history is recorded in [CHANGELOG.md](CHANGELOG.md).

## License / Notice

See [LICENSE](LICENSE) and [NOTICE](NOTICE) for licensing and attribution.
