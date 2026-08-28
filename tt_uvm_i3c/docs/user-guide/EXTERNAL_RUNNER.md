# External Runner Integration

## Purpose

The package-level `run.sh` and `i3c/sim/scripts/` tree are optional reference
automation. They reproduce the delivered VCS, local/Slurm, waveform, and IBI
coverage flows, but they are not runtime dependencies of the SystemVerilog/UVM
environment. An integrator may use DVSim or another orchestration framework.

This document defines the observable contract that an external runner must
preserve. It does not claim that simulators other than the delivered VCS
backend have been qualified.

## Source and Build Contract

The confirmed reference configuration is:

| Item | Value |
|---|---|
| Simulation top | `tb_smc_peripherals_top` |
| Generated compile filelist | `i3c/sim/generated/compile.f` |
| Filelist generator | `i3c/sim/project/generate_dv_inputs.sh` |
| Authoritative test grouping | `i3c/sim/filelists/test.f` |
| Generated normalized plan | `i3c/sim/generated/testplan.dv` |
| External DUT filelist | `${I3C_ROOT_DIR}/src/i3c.f` |
| UVM baseline | Accellera UVM 2020.3.1 |
| UVM register width | `UVM_REG_DATA_WIDTH=128` |
| RTL-mode defines | `SMC_USE_I3C_RTL`, `SMC_USE_I3C_RAL` |
| IBI closure metrics | `assert,group` |

The generated inputs are not versioned release sources. Generate them after
selecting the external DUT and Caliptra checkouts:

```bash
export I3C_ROOT_DIR=/path/to/tt-i3c-core
export CALIPTRA_ROOT=/path/to/caliptra-rtl
i3c/sim/project/generate_dv_inputs.sh
```

The source revisions and validation policy are defined by
`docs/release/SOURCE_BASELINE.md` and `i3c/sim/project/i3c_source_pins.mk`. External
automation must not replace those reviewed revisions silently.

## Test and Runtime Contract

Select a UVM test with the standard `UVM_TESTNAME` mechanism and supply a
reproducible random seed. The authoritative class names, case identifiers,
default seed policy, per-entry plusargs, enable state, and compile requirements
are in the normalized plan generated from `i3c/sim/filelists/test.f`.

The plan distinguishes a UVM test class from a case. Multiple cases may use the
same class with different plusargs. An external runner must preserve the full
tuple:

```text
test class + case identifier + plusargs + seed + compile requirements
```

Do not collapse entries solely because their UVM test class is identical.
Directed entries should retain their planned seed policy; random-seed entries
may be expanded according to the selected regression policy.

Before each test, apply the SVA policy selected by
`i3c/verify/tb/sva/waivers/suite_policies.tsv`, together with the global and
policy-specific lists under `i3c/verify/tb/sva/waivers/`. The reference runner
converts these entries into runtime `+SVA_WAIVE_<key>` plusargs.

## Verdict Contract

A successful simulator process return code alone is insufficient. A case is
PASS only when all applicable conditions hold:

- compile and simulation processes complete successfully;
- a recognized UVM completion summary is present;
- `UVM_ERROR` and `UVM_FATAL` counts are zero;
- no unwaived SVA failure is present;
- no scoreboard mismatch or explicit functional failure is reported;
- no timeout, simulator crash, license failure, or scheduler failure remains;
- an entry carrying `+IBI_REQUIRE_COV` produces its required IBI coverage
  sample.

UVM warnings are reported but do not alone make a case fail. Retry must not
convert a functional failure into PASS. If infrastructure retry is supported,
retain every attempt and admit only the final explicit PASS database to the
coverage merge.

## Coverage Contract

The delivered coverage claim is limited to IBI assertion and functional-group
coverage. It is not full I3C or full-DUT coverage, and RTL code coverage is not
part of the current closure denominator.

For a merged IBI result, external automation must:

1. select the enabled IBI entries from the normalized plan;
2. preserve each entry's case, plusargs, seed, and compile requirements;
3. reject failed or incomplete attempts;
4. merge only the latest accepted PASS database for each eligible case;
5. report the required `assert` and `group` metrics;
6. retain the mapping to `docs/verification/VERIFICATION_PLAN.md` and its
   documented scope, exclusion, and evidence-status dispositions.

The reference VCS flow records hierarchy and group selection in
`i3c/sim/scripts/cov_setup.cfg` and
`i3c/sim/scripts/ibi_group_db_edit.cfg`.

## Artifacts and Reproducibility

An external runner does not need to reproduce the reference directory layout,
console colors, HTML format, burst identifiers, or Slurm behavior. It must
retain enough information to reproduce and audit every result:

- project and DUT revision;
- simulator and UVM versions;
- compile filelist, defines, and options;
- test class, case identifier, plusargs, and seed;
- process return code and UVM/SVA/scoreboard verdict evidence;
- simulation log and waveform location when generated;
- coverage database and merge membership;
- start time, duration, and final status.

The bundled runner remains the reference implementation for candidate
qualification, useful for comparison when validating another orchestration
implementation.

## Support Boundary

The delivered reference runner is validated for the tool and source baseline
listed in the release documentation. DVSim configuration, other simulator
backends, cluster-specific deployment adapters, and customer wrapper hierarchy
changes require separate integration and qualification. Commercial EDA tools
and licenses are not included with this delivery package.
