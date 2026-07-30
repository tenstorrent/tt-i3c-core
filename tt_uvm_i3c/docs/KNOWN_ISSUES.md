# Known Issues

This document distinguishes observed failures from suspected root causes and
from questions that require specification or RTL-owner confirmation.

### Issue Summary

| ID | Problem | Confirmed Behavior | Current Assessment |
|---|---|---|---|
| P1 | IBI descriptor drops the RnW bit under the project-expected HCI layout | For bus header `{DA=0x5a, RnW=1}` (`0xb5`), the DUT produced descriptor `0x01005a01` instead of project-expected `0x0100b501`. | Reconfirmed by `smc_i3c_ibi_controller_timing_context_test`. UVM has been changed to match the current RTL's zero-extended DA, but the encoding remains a compatibility workaround pending RTL/specification confirmation. |
| P2 | DAT no-match policy timing | A no-match request for DA `0x5a` with DAT DA `0x5b` was ACKed. The DUT committed `DATA_LENGTH=3`, success status, MDB, and two payload bytes instead of rejecting the request. | Confirmed functional mismatch in `smc_i3c_ibi_controller_policy_test`. The reverse-lookup timing explanation is plausible from source analysis, but internal RTL correlation is still required. |
| P3 | Post-IBI Controller forward progress | The multi-target test completed its first IBI/HCI check, then the bus left idle during the required `T_AVAL=333` window. The timing-context test completed its initial idle IBI, then the next private write timed out. | Two related post-IBI progress failures are confirmed. A shared root cause, stale-SDA mechanism, or phantom IBI re-entry has not been proven. |
| C1 | Controller STOP SVA checker | `ap_controller_stop_after_response` fired 10 times across the three affected tests. Its implementation treats sampled SDA-high values on SCL rising edges as STOP checks. | Checker defect / unreliable assertion evidence. These failures must not be classified as confirmed RTL STOP violations. |

### P1 — IBI Descriptor Encoding

P1 is reproduced by `smc_i3c_ibi_controller_timing_context_test`. The current
UVM has already been changed to accept the RTL value, but that change aligns
the checker with observed implementation behavior; it does not resolve
whether the implementation follows the required HCI descriptor format.

#### Project-Expected Behavior

For dynamic address `0x5a` and `RnW=1`, the IBI bus header byte is:

```text
{DA[6:0], RnW} = {7'h5a, 1'b1} = 8'hb5
```

Under the project-expected HCI layout:

- descriptor bits `[15:9]` contain `DA[6:0]`;
- descriptor bit `[8]` contains `RnW`;
- descriptor bits `[15:8]` therefore preserve the complete header byte;
- with the remaining observed status fields unchanged, the expected
  descriptor is `0x0100b501`.

#### Actual Behavior and Evidence

`smc_i3c_ibi_controller_timing_context_test` provides a direct
bus-to-descriptor comparison:

- the I3C monitor decoded address `0x5a`;
- the I3C monitor decoded `RnW=1`;
- the transmitted header is therefore `0xb5`;
- the DUT returned `IBI_PORT=0x01005a01`;
- the timing-context sequence also logged
  `descriptor=0x01005a01`.

```text
Bus header        : DA=0x5a, RnW=1 -> 0xb5
Project expected  : 0x0100b501
Actual DUT value  : 0x01005a01
```

This reconfirms that the descriptor byte `[15:8]` contains `0x5a`, not the
complete header byte `0xb5`. The observed value is consistent with recording
a zero-extended DA and omitting RnW from `IBI_ID`.

The other affected Controller tests are consistent with that encoding:

- `smc_i3c_ibi_controller_multi_target_test` read descriptor `0x01005a01`;
- `smc_i3c_ibi_controller_policy_test` read descriptor `0x01005a03`;
- neither test reported an `HCI IBI_ID` mismatch under the current checker.

#### Current UVM Alignment

The current UVM implementation has been modified to match the RTL:

- `smc_i3c_ibi_controller_observer` reads `IBI_ID` from descriptor bits
  `[15:8]`;
- its address-correlation helper recognizes both `{1'b0, DA}` and
  `{DA, 1'b1}` so that either encoding can still be correlated;
- `smc_i3c_ibi_controller_scoreboard` currently expects
  `{1'b0, expected.target_addr}`;
- the bus monitor checks DA and RnW independently from the HCI descriptor.

For DA `0x5a`, the scoreboard therefore expects `IBI_ID=0x5a` and reports a
match for the actual descriptor. This is intentional compatibility with the
current RTL. It must not be interpreted as confirmation that dropping RnW is
the correct HCI encoding.

#### Timing and Suspected RTL Location

The relevant conversion should be inspected where the received IBI header is
packed into the HCI status descriptor:

- likely RTL area: the IBI descriptor packing path in `flow_active.sv`;
- input of interest: the complete received header byte, including RnW;
- output of interest: descriptor bits `[15:8]`;
- suspected transformation: `{1'b0, fmt_byte_1[7:1]}` or an equivalent
  zero-extension of DA instead of preserving `{DA, RnW}`.

The standalone package does not contain the external TT I3C RTL source.
The suspected transformation remains an implementation hypothesis until it is
confirmed from RTL or an internal-signal waveform analysis.

#### Reconfirmation Result

The available evidence supports the following conclusions:

| Question | Result |
|---|---|
| Was the bus header `{DA=0x5a, RnW=1}`? | **Yes.** The monitor independently logged DA `0x5a` and `RnW=1`. |
| Did the DUT produce `0x01005a01` instead of `0x0100b501`? | **Yes.** Both the AXI/RAL read and the timing sequence logged `0x01005a01`. |
| Does the current UVM match the DUT's zero-extended DA? | **Yes.** The scoreboard explicitly expects `{1'b0, DA}`. |
| Is zero-extended DA confirmed as the required HCI encoding? | **No.** No authoritative specification interpretation or RTL-owner decision has been identified. |

#### Question for RTL Designers

Could the RTL owners confirm which definition is required for
descriptor bits `[15:8]`?

1. MIPI/project-expected header encoding: `{DA[6:0], RnW}`, which gives
   `0xb5` for DA `0x5a`, `RnW=1`; or
2. the current RTL custom encoding: `{1'b0, DA[6:0]}`, which gives `0x5a`.

If the first definition is required, the current RTL drops RnW and P1 is an
RTL descriptor-packing defect. If the second definition is intentional, that
custom encoding must be formally confirmed and documented; only then can the
current UVM workaround be considered the final expected behavior.

### P2 — DAT No-Match Policy Failure

`smc_i3c_ibi_controller_policy_test` executed policy case 4 from a clean
reset and reproduced the DAT no-match failure:

```text
DAT dynamic address    = 0x5b
IBI requester address = 0x5a
Expected response      = NACK
Observed response      = ACK
Expected data length   = 0
Observed data length   = 3
Observed data          = MDB 0xa5 plus two payload bytes
Descriptor             = 0x01005a03
```

The Controller scoreboard received one expected event and one actual event.
It completed the case but reported four field mismatches:

1. Controller ACK: expected `0`, actual `1`.
2. HCI `DATA_LENGTH`: expected `0`, actual `3`.
3. HCI `IBI_STATUS`: expected failure (`1`), actual success (`0`).
4. HCI FIFO data: expected no bytes, actual three bytes.

The test ended with 11 UVM errors and four SVA errors. The four scoreboard
mismatches are the decisive functional evidence. Three STOP assertion errors
are C1 checker noise; the `ap_controller_response` failure is consistent with
the independently reported ACK/NACK mismatch.

The current source-level hypothesis is that `flow_active` makes the policy
decision from `dat_rdata` while initiating the reverse lookup for the current
request address. An internal-signal waveform review or RTL instrumentation is
still needed to prove that timing sequence as the root cause.

The current test configuration selects only the DAT no-match case. It does not
establish behavior for the matched-accept, matched-reject, payload-disabled,
or valid-idle false-NACK cases.

### P3 — Post-IBI Controller Forward Progress

P3 currently covers two confirmed symptoms. The current test results do not
yet justify the stronger claim that both symptoms are caused by stale SDA or
a phantom IBI re-entry.

#### Multi-target reproduction

`smc_i3c_ibi_controller_multi_target_test` made the following progress before
failing:

- two DAT entries were programmed for dynamic addresses `0x5a` and `0x5b`;
- the concurrent arbitration phase completed without the sequence's
  arbitration or loser-release fatal checks firing;
- IRQ and the first HCI record were read;
- the Controller scoreboard reported 13 matching fields and no mismatch for
  that first event;
- the subsequent `wait_bus_available()` failed at 25,065 ns because SDA or SCL
  left idle before the full `T_AVAL=333` interval elapsed.

The test ended with one UVM fatal and three C1 STOP assertion errors. It did
not reach the loser retry, second HCI record, or final two-event scoreboard
checks. Therefore it confirms first-event completion followed by a bus-idle
qualification failure; it does not demonstrate successful service of the
loser on retry.

There is also a monitor inconsistency that requires waveform review: during
the concurrent phase, the protocol monitor printed address `0x6d` with
`RnW=0`, while the HCI record and Controller scoreboard matched the expected
winner DA `0x5a`. Until the FSDB is reviewed, this text trace must not be used
as independent proof of a clean on-wire winner address.

#### Timing-context reproduction

`smc_i3c_ibi_controller_timing_context_test` completed the initial
idle-context IBI:

- request released after the legal bus-available window at 6,035 ns;
- bus monitor decoded DA `0x5a`, `RnW=1`, and MDB `0xa5`;
- descriptor `0x01005a01` and MDB `0xa5` were read;
- all 13 Controller scoreboard fields matched.

The sequence then issued the private-write command at 23,895–23,995 ns. The
target never completed that transfer, and the 200,000-cycle forward-progress
sentinel expired at 2,024,005 ns. The test stopped in the first `IDLE` context,
so it did not exercise the `AFTER_XFER` or `BUSY_DEFER` contexts.

This is a confirmed post-IBI private-write stall. It resembles the
multi-target post-event failure, but a common internal cause has not been
proven.

#### Required evidence to close P3

P3 root-cause closure requires waveform correlation of at least:

- SDA/SCL and the DUT pad output-enable signals after STOP;
- Controller command-FSM state and command queue consumption;
- bus-available / `T_AVAL` state;
- IBI request-detect and arbitration state;
- DAT/RLT lookup request, response, and validity signals.

### C1 — Controller STOP SVA Is Not Reliable

The three affected tests report the following
`ap_controller_stop_after_response` counts:

| Test | STOP Assertion Failures | Additional Controller SVA Failure |
|---|---:|---|
| `smc_i3c_ibi_controller_policy_test` | 3 | `ap_controller_response` once |
| `smc_i3c_ibi_controller_multi_target_test` | 3 | None |
| `smc_i3c_ibi_controller_timing_context_test` | 4 | None |

The current assertion implementation updates its STOP check on every rising
edge of SCL. When SDA is sampled high, it clears `in_frame` and emits
`stop_check_pulse`. A protocol STOP, however, is an SDA low-to-high transition
while SCL is high. Because the implementation does not require that SDA
transition, ordinary high data bits can trigger false STOP checks.

Consequences:

- the 10 STOP assertion failures are not reliable evidence of a DUT STOP
  violation;
- they inflate the runner's `ASSERT_FAIL` totals in all three tests;
- they should remain visible, but should be tracked as a checker correction
  rather than waived as a known RTL mismatch.

After correcting the STOP detector, all three tests must be rerun to determine
whether any genuine STOP failure remains.

### Other Open Limitations

| Area | Current Evidence | Current Status |
|---|---|---|
| CSR scoreboard depth | `smc_i3c_ibi_controller_policy_test` observed 45 CSR transactions, but reported zero modeled CSR checks and 45 unmodeled accesses. The other Controller tests also contain extensive `SMC_I3C_SB_UNMODELED` reporting. | In Progress — RAL prediction is active, but the standalone CSR scoreboard is not a full CSR reference model. |
| Duplicate RAL callback warnings | Each affected test reports four `CBPREG` warnings for callbacks already registered on RX/TX data-port registers and fields. | Open — appears non-fatal, but should be removed or documented to reduce warning noise. |
| Controller FIFO/IRQ closure | No dedicated Controller FIFO/IRQ test is currently available. | Planned |
| Retry, MDB decode, pending-read notification, overflow, invalid target, reset, recovery, and random stress | Several dedicated tests are not implemented. | Planned |
| Hot-join | No current implementation. | Blocked |
| Code coverage | No current qualified coverage result is available. | Not measured — line, toggle, FSM, branch, condition, and functional coverage remain open. |

These failures must remain visible. Expected behavior, assertion waivers, and
test status must not be changed solely to obtain a passing result. Closure
requires either a qualified RTL fix, a reviewed checker fix, or an approved
specification interpretation, followed by rerun evidence.
