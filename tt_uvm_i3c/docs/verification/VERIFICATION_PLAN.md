# I3C IBI Verification Plan

This document is the sole authoritative verification plan and
requirement-to-evidence mapping for the delivered I3C In-Band Interrupt
(IBI) scope. It is independent of any specific simulator, coverage database
format, or vendor mapping tool. Tool-specific execution procedures are in
[Qualification](QUALIFICATION.md) and
[Reference runner](../user-guide/REFERENCE_RUNNER.md), not here.

The `IBI-TX-*`, `IBI-RX-*`, `IBI-BUS-*`, and `IBI-ENV-*` identifiers below
are internal UVM verification-objective IDs. The handoff workbook uses the
external verification MAS/spec trace-ID namespace (`I3C-IBI-*`, `I3C-CTRL-IBI-*`,
`I3C-HCI-*`, and `I3C-ERR-*`). Test-class, SVA, coverage, and scoreboard
object names provide the cross-reference between the two namespaces.

The historical external ID `I3C-IBI-009` represented Hot-Join. It is absent
from the current in-scope requirement matrix because the reviewed native RTL does not
implement Hot-Join; its disposition is recorded as KI-002 in
[Known issues](KNOWN_ISSUES.md). Existing external IDs are intentionally not
renumbered.

## 1. Verification Objective

Verify the I3C IBI feature of the DUT in both supported roles:

- **Target-TX** — the DUT acts as an I3C Target issuing IBI requests to a
  Controller.
- **Controller-RX** — the DUT acts as an I3C Controller receiving and
  arbitrating IBI requests from one or more Targets.

The objective is functional and protocol correctness of IBI request,
arbitration, payload/MDB content, policy decisions, queue/interrupt effects,
timing, retry/recovery, and multi-target behavior, backed by directed tests,
constrained-random tests, passive assertions, and functional coverage.

## 2. In-Scope Functionality

- Target-TX IBI request, ACK/NACK response, payload, and mandatory data byte
  (MDB) content.
- Target-TX retry, retry exhaustion, arbitration win/loss, eligibility
  gating, busy-bus deferral, FIFO/IRQ effects, and recovery/cleanup.
- Controller-RX IBI receipt, content/MDB decode, DAT-based payload policy,
  response descriptors, queue/FIFO state, interrupt behavior, and
  reset/flush.
- IBI timing at bus idle, after a normal transfer, and during activity that
  requires deferral.
- Multi-target/multi-requester ordering, arbitration, and DUT win/loss in both
  DUT roles.
- Canonical queue/FIFO/IRQ and recovery-cleanup scenarios in each supported
  role; the compatibility identities do not combine these with additional
  multi-source pressure or live-arbitration recovery injection.
- Directed, constrained-random, multi-seed, and stress scenarios for the
  above.
- Role-independent bus signal integrity and bounded IBI frame/IRQ sanity.
- The minimum CSR/RAL frontdoor access and bus bring-up needed to configure
  and observe the scenarios above.

## 3. Out-of-Scope Functionality

The following are explicitly not claimed by this plan. No requirement below
maps to them, and their absence from the requirement matrix is intentional,
not an oversight:

- Dynamic Address Assignment (DAA/ENTDAA).
- CCC event-control commands (ENEC/DISEC and related CCC handling).
- HDR-mode transfers.
- Legacy I2C mode.
- Full I3C protocol verification or full-DUT verification.
- RTL code-coverage closure.
- AXI/CSR boundary verification beyond the minimum frontdoor access needed
  to configure IBI scenarios (see Known Exclusions).
- Full generated-RAL verification (register-by-register RAL model closure).
- Simulator/tool portability. This plan does not depend on a specific
  simulator; the currently used reference execution flow is described in
  [Qualification](QUALIFICATION.md) and
  [Reference runner](../user-guide/REFERENCE_RUNNER.md).

## 4. Verification Strategy

- A UVM environment drives and monitors the DUT in both IBI roles using a
  shared protocol VIP, with role selection by factory override rather than
  a separate testbench.
- Directed tests exercise specific IBI scenarios (request, retry,
  arbitration, policy, timing, recovery). Constrained-random and stress
  tests exercise the same scenario space with randomized ordering and
  iteration counts.
- Passive SVA checks protocol legality and timing continuously across all
  tests; it does not drive the DUT and does not modify the I3C RTL.
- Functional coverage records requirement-relevant scenario classes
  (role, content, arbitration outcome, policy decision, queue/IRQ state,
  timing context, recovery cause/result) independently of pass/fail
  status, so that closure can be assessed from something other than the
  test list alone.
- Scoreboards and predictors compare observed IBI records and responses
  against the expected model for end-to-end data and HCI-record
  correctness.

## 5. Requirement-to-Evidence Matrix

The authoritative runtime selection, cases, plusargs, and enable state for
every test below are in `i3c/sim/filelists/test.f`. Test names and case IDs
in this table are copied from that file and from the corresponding test
classes under `i3c/verify/tb/tests/`; assertion and coverage object names
are copied from `i3c/verify/tb/sva/` and `i3c/verify/tb/coverage/`.

`Status` reflects recorded execution/closure evidence for the current
candidate baseline as tracked in
[Release manifest](../release/RELEASE_MANIFEST.md), not merely that a test,
assertion, or coverage object is implemented. As of this revision, full
enabled regression and merged assertion/functional-group coverage evidence
for the candidate baseline are recorded as pending in the release manifest;
every requirement below is therefore `Pending` unless otherwise noted, even
though the underlying test, SVA, and coverage objects already exist in the
repository.

### 5.0 Customer compatibility identities

The eight public names below are retained as customer regression/result-
database identities. They are compatibility wrappers, not eight independent
signoff engines. The wrapper behavior and the canonical evidence source are
shown explicitly so the plan does not attribute checks to a name-only wrapper.

| Customer testcase identity | Canonical verification engine(s) | Unique wrapper behavior? | Evidence source | Status |
|---|---|---|---|---|
| `i3c_ibi_target_tx_multi_target_addr_matrix_test` | `i3c_ibi_target_tx_multi_target_vseq` | Identity/report only | Canonical Target-TX multi-target scoreboard/SVA/coverage | Pending |
| `i3c_ibi_target_tx_retry_limit_test` | `i3c_ibi_target_tx_retry_arbitration_vseq` | Truthful single-requester retry-limit identity | Canonical retry-arbitration/retry-exhaustion infrastructure | Pending |
| `i3c_ibi_target_tx_multi_target_timing_test` | `i3c_ibi_target_tx_multi_target_vseq` | Identity/report only | Canonical Target-TX multi-target timing assertions/coverage | Pending |
| `i3c_ibi_target_tx_multi_target_content_test` | `i3c_ibi_target_tx_multi_target_vseq` then `i3c_ibi_target_tx_mdb_payload_vseq` | Sequencing only | Canonical multi-target and MDB/payload scoreboard/SVA/coverage | Pending |
| `i3c_ibi_controller_rx_multi_target_ordering_test` | `i3c_ibi_controller_rx_multi_target_vseq` | Identity/report only | Canonical Controller-RX multi-target scoreboard/SVA/coverage | Pending |
| `i3c_ibi_controller_rx_multi_target_ack_nack_test` | Controller multi-target then `i3c_ibi_controller_rx_policy_vseq` | Restores scalar expected address before policy vseq | Canonical multi-target and policy evidence | Pending |
| `i3c_ibi_controller_rx_multi_target_queue_pressure_test` | Controller multi-target then `i3c_ibi_controller_rx_fifo_irq_vseq` | Restores scalar expected address before FIFO/IRQ vseq | Canonical multi-target and FIFO/IRQ evidence | Pending |
| `i3c_ibi_multi_target_recovery_test` | Controller multi-target then `i3c_ibi_controller_rx_recovery_cleanup_vseq` | Restores scalar expected address; enables recovery checker in `build_phase` | Canonical multi-target and recovery-cleanup evidence | Pending |

These identities preserve the customer contract; they do not claim additional
simultaneous address layouts, mixed per-target policy, multi-source queue
pressure, or recovery injected during live arbitration. A true combined
scenario for any of those behaviors remains a future verification enhancement
unless it is implemented by a canonical engine and mapped separately.

### 5.1 Target-TX (DUT as Target)

| Req ID | Requirement | Test / Case | SVA Evidence | Coverage Evidence | Status |
|---|---|---|---|---|---|
| IBI-TX-01 | Target issues an IBI request and receives an ACK/NACK response on a supported address. | `i3c_ibi_target_tx_basic_test`, `i3c_ibi_target_tx_ack_nack_test` | `ap_target_header`, `ap_target_stop_after_response`, `ap_target_no_data_after_nack`, `cp_target_ibi_ack`, `cp_target_ibi_nack` | `cg_ibi_attempt` (`cp_role`, `cp_target_addr_class`, `cp_ibi_capable`), `cg_ibi_completion` (`cp_response`) | Pending |
| IBI-TX-02 | Target IBI payload and mandatory data byte (MDB) content is correctly formed. | `i3c_ibi_target_tx_mdb_payload_test` | `ap_ibi_mdb_presence_matches_descriptor`, `ap_ibi_payload_length_matches_descriptor`, `ap_ibi_mdb_value_matches_descriptor`, `ap_ibi_mdb_group_decode`, `cp_ibi_with_mdb`, `cp_ibi_with_payload` | `cg_ibi_completion` (`cp_mdb_present`, `cp_mdb_group`, `cp_payload_len`) | Pending |
| IBI-TX-03 | Target retries an IBI request within a bounded retry count across payload lengths, including retry exhaustion. | `i3c_ibi_target_tx_retry_arbitration_test` (15 cases: `retry_one_*`, `retry_few_*`, `retry_many_*`), `i3c_ibi_target_tx_retry_exhaustion_test` (`retry_exhaust_few`), `i3c_ibi_target_tx_retry_limit_test` (truthful single-requester retry-limit identity) | `ap_ibi_retry_count_bounded`, `ap_ibi_nack_stops_or_retries` | `cg_ibi_completion` (`cp_retry_count`), `cg_ibi_recovery` (`cp_cause`, `cp_result`) | Pending |
| IBI-TX-04 | Target arbitration outcome (win/loss) against other bus requesters is correctly observed and the loser releases the bus, including multi-requester loss correlation. | `i3c_ibi_target_tx_multi_target_test`, `i3c_ibi_target_tx_multi_target_addr_matrix_test` (compatibility identity for the canonical engine), `i3c_ibi_target_tx_dut_loss_test` (7 entries including the default case), `i3c_ibi_target_tx_dut_win_test` (4 entries including the default case) | `ap_ibi_arbitration_context`, `ap_ibi_arbitration_single_winner`, `ap_ibi_loser_releases_sda`, `ap_target_releases_after_arbitration_loss`, `ap_target_releases_response_bit` | `cg_ibi_attempt` (`cp_requester_count`, `cp_arb_outcome`, `x_arb`) | Pending |
| IBI-TX-05 | Target does not start an illegal IBI when IBI is disabled, the address is not eligible, or the bus is busy; a legal request on an idle bus is not blocked. | `i3c_ibi_target_tx_invalid_target_test` (`i3c_ibi_runtime_negative`), `i3c_ibi_target_tx_busy_bus_block_test` (`i3c_ibi_coverage`) | `ap_ibi_start_only_when_enabled`, `ap_ibi_no_request_when_busy`, `ap_ibi_valid_target_only`, `ap_ibi_request_on_bus_idle` | `cg_ibi_attempt` (`cp_event_enable`, `cp_ibi_capable`, `cp_bus_state`), `cg_ibi_blocked` (`cp_start_blocked`, `cp_request_busy`, `cp_deferred`) | Pending |
| IBI-TX-06 | An accepted or rejected IBI updates FIFO/IRQ state correctly, including full-queue rejection without a partial commit. | `i3c_ibi_target_tx_fifo_irq_test`, `i3c_ibi_target_tx_overflow_test` (`i3c_ibi_wip`) | `ap_ibi_irq_has_status_source`, `ap_ibi_irq_enable_gating`, `ap_ibi_irq_w1c_clears_status`, `ap_ibi_accepted_updates_fifo`, `ap_ibi_full_rejects_without_commit` | `cg_ibi_queue_irq` (all coverpoints) | Pending |
| IBI-TX-07 | Target recovers and cleans up pending IBI state after a partial or aborted IBI sequence. | `i3c_ibi_target_tx_partial_recovery_test`, `i3c_ibi_target_tx_recovery_cleanup_test` (`i3c_ibi_wip`) | `ap_ibi_recovery_cleanup`, `ap_ibi_flush_clears_pending_state`, `ap_ibi_cleanup_forward_progress`, `cp_ibi_recovery_target` | `cg_ibi_recovery` (`cp_trigger_seen`, `cp_queue_empty`, `cp_forward_progress`) | Pending |
| IBI-TX-08 | A Target IBI queued during a normal transfer preserves that transfer, waits through the programmed Bus Available interval, and starts legally afterward. | `i3c_ibi_target_tx_busy_bus_block_test`, `i3c_ibi_target_tx_multi_target_timing_test` (compatibility identity for the canonical multi-target engine; no special timing plusargs) | `ap_ibi_no_request_when_busy`, `ap_ibi_after_transfer_starts_after_normal`, `cp_ibi_target_after_normal_transfer`; the canonical busy-bus and multi-target engines provide the physical START/STOP, ownership and `T_AVAL` evidence | `cp_ibi_after_normal_transfer`, `cg_ibi_attempt` (`cp_bus_state.after_transfer`), `cg_ibi_blocked` (`cp_transfer_preserved`, `cp_retry_after_idle`) | Pending |
| IBI-TX-09 | Constrained-random and stress IBI generation reach the required scenario mix under randomized ordering for cases that enable `+IBI_RANDOM_MUST_HIT=1`; other cases reach only a planned scenario mix with no enforced bucket-closure gate. | `i3c_ibi_target_tx_random_test` (`closure_24`, `+IBI_RANDOM_MUST_HIT=1`), `i3c_ibi_target_tx_stress_test` (`mixed_response_60`, `+IBI_RANDOM_MUST_HIT=1`; `ack_burst_100`, no must-hit flag — planned mix only) | Exercises the assertions listed in IBI-TX-01..07 under randomized stimulus; `closure_24`/`mixed_response_60` additionally `uvm_fatal` (tag `IBI_RANDOM_MUST_HIT`) if any of 15 required MDB/payload/response/retry/gap buckets is missed | Contributes to `cg_ibi_attempt` / `cg_ibi_completion` bins under randomized profiles | Pending |
| IBI-TX-10 | Multi-target address arbitration is exercised with three configured Target slots; retry-limit behavior remains covered by the canonical retry-arbitration engine. | `i3c_ibi_target_tx_multi_target_test`, `i3c_ibi_target_tx_multi_target_addr_matrix_test` (compatibility identity), `i3c_ibi_target_tx_retry_arbitration_test` | `ap_ibi_arbitration_single_winner`, `ap_ibi_loser_releases_sda`, `ap_ibi_retry_count_bounded` | `cg_ibi_attempt` (`x_arb`), `cg_ibi_completion` (`cp_retry_count`) | Pending |
| IBI-TX-11 | IBI content is correct for the canonical Target-TX payload scenario; the compatibility content identity runs that scenario after canonical multi-target behavior. | `i3c_ibi_target_tx_mdb_payload_test`, `i3c_ibi_target_tx_multi_target_test`, `i3c_ibi_target_tx_multi_target_content_test` (compatibility identity; no per-requester simultaneous content contract) | `ap_ibi_mdb_presence_matches_descriptor`, `ap_ibi_payload_length_matches_descriptor`, `ap_ibi_mdb_value_matches_descriptor`, `ap_ibi_mdb_group_decode`; `cp_ibi_with_mdb`, `cp_ibi_with_payload` | `cg_ibi_completion` (`x_content`) | Pending |

### 5.2 Controller-RX (DUT as Controller)

| Req ID | Requirement | Test / Case | SVA Evidence | Coverage Evidence | Status |
|---|---|---|---|---|---|
| IBI-RX-01 | Controller receives an IBI request and issues the correct ACK/NACK response. | `i3c_ibi_controller_rx_basic_test` | `ap_ibi_header`, `ap_controller_response`, `ap_controller_stop_after_response`, `cp_ibi_address_ack`, `cp_ibi_address_nack` | `cg_ibi_completion` (`cp_response`) | Pending |
| IBI-RX-02 | Controller decodes IBI content and MDB correctly across payload lengths (0, 1, 3, 4, 7, 10 bytes). | `i3c_ibi_controller_rx_content_test` (6 cases: `content_mdb_only` .. `content_long`), `i3c_ibi_controller_rx_mdb_decode_test` (`i3c_ibi_wip`) | `ap_ibi_mdb_presence_matches_descriptor`, `ap_ibi_payload_length_matches_descriptor`, `ap_ibi_mdb_value_matches_descriptor`, `ap_ibi_mdb_group_decode` | `cg_ibi_completion` (`cp_mdb_present`, `cp_mdb_group`, `cp_payload_len`, `x_content`) | Pending |
| IBI-RX-03 | Controller applies DAT-based payload policy correctly (accept, reject, payload-disabled, no-match). | `i3c_ibi_controller_rx_policy_test` (`policy_dat_accept`, `policy_dat_reject`, `policy_payload_disabled` in `i3c_ibi_coverage`; `policy_dat_no_match` in `i3c_ibi_validated_rechecks`) | `ap_ibi_controller_policy`, `ap_ibi_rejected_no_payload_commit` | `cg_ibi_completion` (`cp_dat_decision`, `cp_payload_policy`, `x_policy`) | Pending |
| IBI-RX-04 | Controller IBI timing behavior is correct at bus idle, after a transfer, and under busy-bus deferral. | `i3c_ibi_controller_rx_timing_context_test` (`timing_idle`, `timing_after_xfer`, `timing_busy_defer`); its vseq contains explicit legality and response checks (`uvm_fatal`/`uvm_error` tags `IBI_TIMING_ILLEGAL_START`, `IBI_TIMING_EARLY_IRQ`, `IBI_TIMING_EARLY_RECORD`, `IBI_TIMING_NORMAL_RESPONSE`, `IBI_TIMING_IBI_ID`, `IBI_TIMING_IBI_DATA`, `IBI_TIMING_EVENT_COUNT`, `IBI_TIMING_BUSY_COVERAGE`, `IBI_TIMING_RETRY_COVERAGE`) plus a scoreboard-mismatch gate (`IBI_TIMING_SCOREBOARD`), not merely coverage sampling | `ap_ibi_request_on_bus_idle`, `ap_ibi_after_transfer_starts_after_normal`, `cp_ibi_controller_after_normal_transfer` | `timing_context_cg` (`cp_context`, `cp_request_busy`, `cp_deferred`), `cp_ibi_after_normal_transfer` | Pending |
| IBI-RX-05 | Controller queue/FIFO commit and interrupt behavior are correct for accepted, rejected, and full-queue conditions. | `i3c_ibi_controller_rx_fifo_irq_test` (`i3c_ibi_validated_rechecks`) | `ap_ibi_accepted_updates_fifo`, `ap_ibi_full_rejects_without_commit`, `ap_ibi_irq_has_status_source`, `ap_ibi_irq_enable_gating`, `ap_ibi_irq_w1c_clears_status` | `cg_ibi_queue_irq` | Pending |
| IBI-RX-06 | Controller reset/flush clears pending IBI state. | `i3c_ibi_controller_rx_reset_flush_test` (`i3c_ibi_wip`) | `ap_ibi_flush_clears_pending_state`, `ap_ibi_recovery_cleanup` | `cg_ibi_recovery` | Pending |
| IBI-RX-07 | Controller pending-read notification follows the advertised HCI Auto-Command contract. | `i3c_ibi_controller_rx_pending_read_notification_test` (`i3c_ibi_wip`) | `ap_ibi_pending_read_event_classify` | `cp_ibi_pending_read_notification` | Pending |
| IBI-RX-08 | Controller handles queue overflow pressure without a partial or incorrect commit. | `i3c_ibi_controller_rx_overflow_test` (`i3c_ibi_wip`; reuses `i3c_ibi_controller_rx_fifo_irq_vseq` with `require_ibi_controller_record_irq` relaxed; the Controller-role scoreboard remains active) | `ap_ibi_full_rejects_without_commit`; the reused vseq's embedded HCI/queue-depth/threshold/order checks (tags `IBI_CTRL_FIFO_DEPTH`, `IBI_CTRL_FIFO_BELOW_THLD`, `IBI_CTRL_FIFO_IRQ_COUNT`, `IBI_CTRL_FIFO_DRAIN`, `IBI_CTRL_FIFO_SB`) | `cg_ibi_queue_irq` (`cp_fifo_level`, `cp_queue_state`, `cp_threshold_relation`) | Pending |
| IBI-RX-09 | Controller recovers and cleans up IBI state after an aborted sequence. | `i3c_ibi_controller_rx_recovery_cleanup_test` (`i3c_ibi_wip`) | `ap_ibi_recovery_cleanup`, `cp_ibi_recovery_controller` | `cg_ibi_recovery` | Pending |
| IBI-RX-10 | Controller-side constrained-random policy sweep is exercised across seeds. | `i3c_ibi_controller_rx_random_test` (`policy_seed_sweep`) | Exercises the assertions listed in IBI-RX-01..03 under randomized policy selection | Contributes to `cg_ibi_completion` policy/response bins | Pending |
| IBI-RX-11 | Controller receives IBI requests from four independently configured UVM Target agents. | `i3c_ibi_controller_rx_multi_target_test`, `i3c_ibi_controller_rx_multi_target_ordering_test` (compatibility identity for the canonical four-target engine) | `ap_ibi_arbitration_single_winner`, `ap_ibi_loser_releases_sda` | `cg_ibi_attempt` (`cp_requester_count`, `x_arb`) | Pending |
| IBI-RX-12 | Controller multi-target ordering/arbitration is evidenced by the canonical engine; policy and FIFO/IRQ behavior are covered by their canonical follow-on engines. | `i3c_ibi_controller_rx_multi_target_test`, `i3c_ibi_controller_rx_multi_target_ordering_test`, `i3c_ibi_controller_rx_multi_target_ack_nack_test`, `i3c_ibi_controller_rx_multi_target_queue_pressure_test`, `i3c_ibi_controller_rx_policy_test`, `i3c_ibi_controller_rx_fifo_irq_test` (compatibility identities do not add simultaneous mixed policy or multi-source queue pressure) | `ap_ibi_arbitration_single_winner`, `ap_ibi_loser_releases_sda`, `ap_ibi_controller_policy`, `ap_ibi_rejected_no_payload_commit`, `ap_ibi_accepted_updates_fifo`, `ap_ibi_full_rejects_without_commit`, `ap_ibi_irq_has_status_source`, `ap_ibi_irq_enable_gating`, `ap_ibi_irq_w1c_clears_status` | `cg_ibi_attempt` (`cp_requester_count`, `x_arb`), `cg_ibi_completion` (`cp_dat_decision`, `x_policy`), `cg_ibi_queue_irq` | Pending |
| IBI-RX-13 | Controller recovery cleanup is exercised after the canonical multi-target sequence; recovery injected during active arbitration is a future verification gap. | `i3c_ibi_multi_target_recovery_test` (compatibility identity), `i3c_ibi_controller_rx_recovery_cleanup_test` | `ap_ibi_recovery_cleanup`, `cp_ibi_recovery_controller` | `cg_ibi_recovery` (`cp_trigger_seen`, `cp_queue_empty`, `cp_irq_low`, `cp_bus_idle`, `cp_forward_progress`) | Pending |

### 5.3 Role-Independent Bus and Supporting Environment

| Req ID | Requirement | Test / Case | SVA Evidence | Coverage Evidence | Status |
|---|---|---|---|---|---|
| IBI-BUS-01 | Bus signal integrity, bounded IBI frame length, and IRQ-line sanity hold regardless of DUT role. | Exercised continuously by every test in 5.1/5.2, not a standalone test | `ap_bus_known`, `ap_dut_drive_known`, `ap_ibi_frame_bounded`, `ap_irq_known`, `ap_reset_releases_sda`, `cp_ibi_frame_complete`, `cp_ibi_irq_asserted` | N/A | Pending |
| IBI-ENV-01 | The minimum CSR/RAL frontdoor access and bus bring-up needed to configure IBI scenarios function correctly. `i3c_ral_all_regs_test` provides supporting-environment RAL frontdoor sanity only; it is not a claim of full generated-RAL verification (register-by-register RAL model closure remains out of scope, Section 3). | `i3c_csr_smoke_test`, `i3c_sanity_test` (`i3c_smoke`), `i3c_ral_all_regs_test` (`i3c_ral`) | `ap_aw_stable`, `ap_w_stable`, `ap_ar_stable`, `ap_b_stable`, `ap_r_stable` (AXI/HCI boundary handshake only) | N/A | Pending — AXI/HCI access-policy behavior remains out of scope |

## 6. Evidence and Status Model

- Evidence for a requirement is its test/case, SVA, and functional-coverage
  objects, read together. A test alone is not closure evidence.
- Functional coverage groups and coverpoints record scenario classes
  independently of pass/fail; assertions record protocol legality
  continuously; the combination is what closes a requirement.
- Coverage results must be obtained from the merged coverage result
  produced by the qualified regression flow for the candidate baseline, not
  from a stale or previously reviewed result. A stale merged result cannot
  prove newly added or renamed evidence objects.
- Status terms used in this document:
  - `Measured` — recorded PASS/closure evidence exists for the candidate
    baseline in the release manifest.
  - `Pending` — the test, SVA, and coverage objects exist and are mapped,
    but recorded execution/closure evidence for the candidate baseline is
    not yet available.
  - `Out of Scope` — intentionally not claimed by this plan (see Section 3).
  - `Not Applicable` — the requirement does not apply to the current reviewed
    RTL baseline (see Known Exclusions and Known issues).
  - `Not Measured` — no executable measurement is claimed for this item; it
    does not mean measured zero.
- Recovery/negative-path failures are checked as test failures. Ignored
  negative-recovery coverage bins are a scope decision, not a waiver.
  Eligibility cases that legally block an IBI START are verified as
  negative-policy evidence rather than by forcing an illegal bus attempt.

## 7. Regression Strategy

- Directed tests use a fixed seed; constrained-random and stress tests use
  multiple seeds and iteration counts as configured in
  `i3c/sim/filelists/test.f`.
- Tests are organized into named groups (for example
  `i3c_ibi_coverage`, `i3c_ibi_multi_target_controller`,
  `i3c_ibi_validated_rechecks`, `i3c_ibi_rtl_unsupported`) with an explicit enabled/disabled state per
  group; disabled groups are excluded from ordinary regression selection.
- The `i3c_ibi_wip` group is enabled and runnable but is not by itself
  release-qualified evidence; see QL-001 in
  [Known issues](KNOWN_ISSUES.md).
- The full qualification execution procedure, including native source
  selection and revision recording,
  compile, regression, and coverage collection commands, is defined in
  [Qualification](QUALIFICATION.md).

## 8. Pass/Fail Expectations

A case is expected to PASS only when the simulation completes, reaches a
recognized UVM completion summary, and no functional failure is observed.
A functional failure includes an unwaived assertion failure, a scoreboard
mismatch, or missing required IBI coverage sampling for a qualifying entry.
The detailed, tool-level pass/fail contract is defined in the package
[README](../../README.md) and in
[External runner](../user-guide/EXTERNAL_RUNNER.md) for third-party
orchestration.

## 9. Coverage and Closure Criteria

- Closure for the IBI scope is owned by the six functional covergroups
  (`cg_ibi_attempt`, `cg_ibi_completion`, `cg_ibi_recovery`,
  `cg_ibi_queue_irq`, `cg_ibi_blocked`, `timing_context_cg`) and by the SVA
  assertions and cover properties listed in Section 5.
- RTL code coverage and non-IBI boundary coverage are outside this plan's
  closure denominator; they must not be added to it merely to raise an IBI
  score.
- No assertion waivers are defined in the delivered baseline. Waiver lists
  under `i3c/verify/tb/sva/waivers/` require joint review with this plan and
  with recorded qualification evidence before use.

## 10. Known Exclusions and Limitations

- **DAA, CCC, HDR, legacy I2C**: out of scope by design (Section 3); this
  IBI-focused environment has no requirement-specific tests or coverage for
  them, and none are claimed.
- **IBI without a mandatory data byte**: not scored. `cp_mdb_present`
  carries `option.weight = 0`, and `cp_mdb_capable` ignores the BCR[2]=0
  case. `i3c_ibi_controller_rx_no_mdb_test` is a focused positive
  Controller-RX RTL-defect reproduction, disabled from ordinary regression
  in `i3c_ibi_rtl_unsupported` until RTL/design resolution; it does not claim
  coverage closure. The Target-TX role has no reviewed descriptor/programming
  contract for requesting a no-MDB IBI and therefore has no synthetic
  no-MDB test. See KI-004 in [Known issues](KNOWN_ISSUES.md) for the Target
  and Controller RTL evidence.
- **AXI/HCI boundary policy**: access-denial behavior is outside this IBI
  verification plan; no verification-owned access policy is modeled.
- **Controller HCI `SOFT_RST` self-clear**: not implemented on the reviewed
  RTL revision and therefore not part of the requirement matrix; see KI-001 in
  [Known issues](KNOWN_ISSUES.md).
- **Hot-join**: unimplemented dead state on the reviewed native RTL (unreachable
  `DoHotJoin`, `hotjoin_done` tied constant). Out of scope for this
  IBI-focused plan by design (Section 3); recorded for handoff completeness
  as KI-002 in [Known issues](KNOWN_ISSUES.md), not as a requirement gap.
- **IBI status-type coverage**: the reviewed Controller RTL only ever produces
  `RegularIBI` for `ibi_status_type`; the other four defined values are
  never assigned, next to the RTL author's own open item (`flow_active.sv`
  TODO #95758). Not yet dispositioned as in-scope or out-of-scope; see
  KI-003 in [Known issues](KNOWN_ISSUES.md) for the open question to the
  RTL author. No requirement in Section 5 currently claims the other four
  values.
- Detailed, individually tracked issues and their disposition are in
  [Known issues](KNOWN_ISSUES.md); this section summarizes only the
  exclusions that shape the requirement matrix above.
