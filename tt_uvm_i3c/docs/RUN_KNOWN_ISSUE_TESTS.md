# Running Known-Issue Tests

This runbook describes how to reproduce, inspect, and report the known I3C
Controller issues tracked in [KNOWN_ISSUES.md](KNOWN_ISSUES.md). It does not
change checker expectations or waive failures to obtain a passing result.

## 1. Scope

The following issues are covered:

| ID | Test | Purpose |
|---|---|---|
| P1 | `smc_i3c_ibi_controller_timing_context_test` | Compare the on-wire IBI header with the HCI IBI descriptor encoding |
| P2 | `smc_i3c_ibi_controller_policy_test` | Reproduce the DAT no-match ACK and payload-commit mismatch |
| P3a | `smc_i3c_ibi_controller_multi_target_test` | Reproduce the post-winner bus-availability/forward-progress failure |
| P3b | `smc_i3c_ibi_controller_timing_context_test` | Reproduce the post-IBI private-write forward-progress failure |
| C1 | All three tests above | Identify the known unreliable Controller STOP assertion separately from functional RTL evidence |

Run these tests as defect-reproduction and diagnostic tests. A known RTL or
checker defect remains visible in the test verdict until it is fixed and the
test is rerun.

## 2. Prerequisites

Run every command from the `tt_uvm_i3c` package root. Do not invoke scripts
directly from `i3c/sim/vcs_run_script/`.

The environment requires:

- Synopsys VCS 2020.12 or newer;
- a recursive TT I3C checkout containing `src/i3c.f`;
- the corresponding Caliptra RTL dependency;
- Verdi and a compatible VCS PLI installation when FSDB generation or viewing
  is required;
- a working simulator license and either local execution or a configured
  Slurm environment.

The default qualification flow uses the bundled UVM 2020.3.1 library.

## 3. Environment Setup

For direct local execution:

```bash
cd /path/to/tt_uvm_i3c

export I3C_ROOT_DIR=/path/to/tt-i3c-core
export SOURCE_MODE=pinned
export DV_DEFAULT_SCHEDULER=local
export DV_VIEW_SCHEDULER=local

source ./run.sh env

./run.sh generate
./run.sh doctor
```

Use `SOURCE_MODE=pinned` when reproducing the recorded qualification baseline.
Use `SOURCE_MODE=worktree` only for an explicitly reviewed modified checkout,
and record the commit and local diff with the result. A dirty-source warning is
not proof that a run is reproducible.

For Slurm execution, select the site-supported scheduler and partition:

```bash
export DV_DEFAULT_SCHEDULER=slurm
export DV_VIEW_SCHEDULER=slurm
export RUNNER_SLURM_PARTITION=<partition-name>
```

## 4. Baseline Validation

Generate the normalized inputs and validate the source/tool environment before
running a defect-reproduction test:

```bash
./run.sh generate
./run.sh doctor
./run.sh list-tests
```

An optional compile-only check is:

```bash
./run.sh comp --show-output
```

The `test` command compiles a matching simulation image by default. When a
waveform format is selected, allow the test command to compile the image with
the required dump instrumentation. Do not reuse a `simv` compiled for a
different dump format.

Use seed `1` for the first reproduction. Record any additional seed explicitly
rather than relying only on a random regression.

## 5. Reproducing P1: IBI Descriptor Encoding

Run the timing-context test in the isolated idle context:

```bash
./run.sh test \
  -t smc_i3c_ibi_controller_timing_context_test \
  --seed 1 \
  --plusargs "+IBI_TIMING_CONTEXT=IDLE" \
  --dump-format fsdb \
  --show-output
```

If FSDB support is unavailable, omit the dump option for a log-only run or use
`--dump-format vcd` for a portable waveform.

### Expected comparison

For dynamic address `0x5a` and `RnW=1`:

```text
On-wire header              : {DA=0x5a, RnW=1} = 0xb5
Project-expected descriptor : 0x0100b501
Current RTL descriptor      : 0x01005a01
```

Correlate the following evidence:

1. the I3C monitor independently decodes `DA=0x5a` and `RnW=1`;
2. the AXI/RAL read returns the HCI IBI descriptor;
3. descriptor bits `[15:8]` contain `0x5a` rather than the complete header
   byte `0xb5`.

The current scoreboard accepts the RTL-compatible `{1'b0, DA}` encoding.
Therefore, a passing scoreboard result does not prove that the encoding meets
the required HCI specification. Final classification requires an authoritative
specification interpretation or RTL-owner confirmation.

## 6. Reproducing P2: DAT No-Match Policy

Run the Controller policy test from a clean simulation reset:

```bash
./run.sh test \
  -t smc_i3c_ibi_controller_policy_test \
  --seed 1 \
  --dump-format fsdb \
  --show-output
```

The current source configuration is:

```systemverilog
RUN_ALL_IN_ONE_SEQ = 0;
ACTIVE_POLICY_CASE = 4;
```

This selects only the `DAT no-match` case so that it runs as the first IBI in
a fresh simulation. The selector is source-level and has no plusarg override.
Some adjacent comments still describe the former all-cases mode as the current
default; use the localparam values above as the executable source of truth.

### Expected and observed behavior

| Field | Expected | Current RTL behavior |
|---|---:|---:|
| DAT address | `0x5b` | `0x5b` |
| Requester address | `0x5a` | `0x5a` |
| Controller response | NACK | ACK |
| HCI `DATA_LENGTH` | `0` | `3` |
| HCI `IBI_STATUS` | Failure | Success |
| Committed data | None | MDB plus two payload bytes |

Search the normalized simulation log for these report IDs and checker output:

```text
IBI_CTRL_POLICY_RESPONSE
IBI_CTRL_POLICY_DESCRIPTOR_STATUS
IBI_CTRL_POLICY_REJECTED_DATA
SMC_I3C_IBI_CTRL_SB
```

The decisive evidence is the independent Controller scoreboard comparison of
the expected policy result with the bus, HCI descriptor, and FIFO data. STOP
assertion failures alone are not decisive evidence for P2; see C1 below.

## 7. Reproducing P3a: Multi-Target Forward Progress

Run the multi-target test:

```bash
./run.sh test \
  -t smc_i3c_ibi_controller_multi_target_test \
  --seed 1 \
  --dump-format fsdb \
  --show-output
```

### Intended flow

1. Program DAT entries for the primary and secondary Target addresses.
2. Start two Target IBI requests concurrently.
3. Observe one Target win arbitration and the other release the bus.
4. Read and check the winner HCI record and IRQ.
5. Qualify the idle bus for the required `T_AVAL` interval.
6. Retry the losing Target.
7. Read and check the second HCI record and IRQ.

### Current failure point

The first event can complete with a matching HCI record and Controller
scoreboard result. The subsequent bus-availability check can then fail before
the loser retry because SDA or SCL does not remain idle for the complete
qualification interval.

Search for:

```text
IBI_CTRL_MULTI_TIMEOUT
IBI_CTRL_MULTI_ARBITRATION
IBI_CTRL_MULTI_RELEASE
IBI_BUS_IDLE_TIMEOUT
IBI_CTRL_MULTI_EVENT_COUNT
```

The protocol monitor has previously printed an address inconsistent with the
HCI record during the concurrent phase. Do not use that text trace alone as
proof of the on-wire winner address. Correlate SDA/SCL, both Target drivers,
the DUT pad output enables, and the HCI record in the waveform.

## 8. Reproducing P3b: Timing-Context Forward Progress

Run all timing contexts:

```bash
./run.sh test \
  -t smc_i3c_ibi_controller_timing_context_test \
  --seed 1 \
  --plusargs "+IBI_TIMING_CONTEXT=ALL" \
  --dump-format fsdb \
  --show-output
```

The supported context selectors are:

```text
+IBI_TIMING_CONTEXT=IDLE
+IBI_TIMING_CONTEXT=AFTER_XFER
+IBI_TIMING_CONTEXT=BUSY_DEFER
+IBI_TIMING_CONTEXT=ALL
```

Use an individual selector to isolate a context after recording the result of
the default all-context diagnostic.

### Current failure point

The initial idle-context IBI can complete, produce an HCI descriptor and MDB,
and match all Controller scoreboard fields. The following private write can
then fail to complete and hit the forward-progress timeout. When this occurs,
the test does not provide evidence for the later `AFTER_XFER` and `BUSY_DEFER`
contexts because it did not reach them.

Search for:

```text
IBI_TIMING_NORMAL_TIMEOUT
IBI_TIMING_NORMAL_TRANSFER
IBI_TIMING_IBI_TIMEOUT
IBI_TIMING_SCOREBOARD
IBI_BUS_IDLE_TIMEOUT
```

For root-cause analysis, correlate at least:

- SDA/SCL and DUT pad output-enable signals after STOP;
- the Controller command FSM and command queue consumption;
- bus-available and `T_AVAL` state;
- IBI request-detect and arbitration state;
- DAT/RLT lookup request, response, and validity signals.

## 9. C1: Known Controller STOP Checker Defect

`ap_controller_stop_after_response` is not currently reliable. Its detector
can treat an SDA-high sample on an SCL rising edge as a STOP check without
requiring the protocol-defined SDA low-to-high transition while SCL is high.
Ordinary high data bits can therefore produce false STOP assertion failures.

Apply the following rules:

- keep the assertion failure visible in logs and summaries;
- classify it as a checker issue, not as a confirmed RTL STOP defect;
- do not waive it solely to convert the test to PASS;
- do not let it replace independent scoreboard or protocol evidence;
- rerun all affected tests after the STOP detector is corrected.

An `ap_controller_response` failure can still be relevant when it agrees with
an independently observed ACK/NACK mismatch.

## 10. Inspecting Results

Inspect the latest or a selected run summary:

```bash
./run.sh summary
./run.sh summary --id <RUN_ID> --tail 200
./run.sh summary --id <RUN_ID> --show
```

Inspect the matching test log:

```bash
./run.sh view --log --last \
  --test <TEST_NAME> --seed 1 --tail 200
```

List waveform artifacts before selecting one:

```bash
./run.sh view
./run.sh view --any-dump --limit 20
```

Open the latest matching FSDB:

```bash
./run.sh view --open --last \
  --test <TEST_NAME> --seed 1 --fsdb
```

For local Verdi viewing:

```bash
export DV_VIEW_SCHEDULER=local
./run.sh view --open --last \
  --test <TEST_NAME> --seed 1 --fsdb
```

## 11. Artifact Layout

A single-test run stores its artifacts under:

```text
i3c/sim/out/runs/<run-id>/
|-- run.meta
|-- compile.meta
|-- logs/compile/compile.log
|-- cases/<test>/seed_<seed>/attempt_001/
|   |-- command.sh
|   |-- logs/sim.log
|   |-- logs/sim.clean.log
|   |-- dumps/<test>_seed_<seed>_attempt_1.<format>
|   `-- coverage/<test>.vdb
`-- summary/
    |-- test.log
    |-- test.errors.log
    |-- failure_quick_links.log
    |-- artifacts.tsv
    `-- seeds.latest.tsv
```

Preserve at least:

- `run.meta` and `compile.meta`;
- the exact `command.sh`;
- `logs/sim.log` and `logs/sim.clean.log`;
- `summary/test.log` and `summary/test.errors.log`;
- the waveform when signal-level correlation is required;
- the external I3C and Caliptra revisions;
- any reviewed worktree diff used by the run.

## 12. Result Classification

Use the following classifications:

| Classification | Meaning |
|---|---|
| `PASS` | Compile and simulation complete with no required UVM error/fatal, assertion failure, scoreboard mismatch, or functional timeout |
| `COMPILE_FAIL` | Compilation or elaboration does not produce a runnable image |
| `INFRA_FAIL` | The run cannot complete because of a license, tool, scheduler, node, or filesystem failure |
| `VERIFICATION_FAIL` | The simulation detects incorrect DUT, testbench, checker, or protocol behavior |

A suspected or known RTL defect remains `VERIFICATION_FAIL` until triage and
rerun evidence establish a qualified fix. A known checker defect may be noted
as `NEEDS_REVIEW`, but it must not be converted to `PASS` while the required
assertion failure remains present.

Do not repeatedly retry a `VERIFICATION_FAIL` solely to obtain a passing
attempt. A later passing attempt does not erase the original failing result.

## 13. Reporting Checklist

Record the following information for every reproduced issue:

```text
Issue ID:
Test:
Seed:
Run ID:
I3C commit:
Caliptra commit:
SOURCE_MODE:
Local source changes:
Scheduler:
VCS version:
Expected behavior:
Observed behavior:
First decisive mismatch:
UVM warning/error/fatal counts:
SVA failures:
Scoreboard result:
Simulation log:
Waveform:
Classification:
Owner or follow-up action:
```

When reporting P1, distinguish an RTL-compatible scoreboard match from an
authoritative HCI encoding decision. When reporting P2 or P3, identify the
independent functional evidence separately from C1 STOP assertion noise.
