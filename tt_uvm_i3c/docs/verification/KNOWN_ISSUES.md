# Known Issues and Qualification Limits

This file classifies unresolved items for the current delivery candidate. The
authoritative enable state is `i3c/sim/filelists/test.f`.

## KI-001: Controller SOFT_RST self-clear is unsupported

- Test: `i3c_ibi_controller_rx_soft_rst_selfclear_test`
- Group: `i3c_ibi_rtl_unsupported` (`off`)
- Classification: the reviewed native RTL does not implement the tested HCI self-clear
  behavior.
- RTL evidence: `src/hci/hci.sv` in the reviewed TT source assigns
  `hwif_base_o.RESET_CONTROL.SOFT_RST = '0`; no reset consumer is connected to
  clear the request.
- Policy: `i3c_ibi_controller_rx_soft_rst_selfclear_test` is the active
  self-clear bug reproduction. Retain it, exclude it from ordinary regression,
  and run it only with `--include-off` when checking a newer RTL revision.

## Qualification limits

The following entries describe evidence maturity and runner policy. They are
not RTL/design issues and therefore use the `QL` namespace rather than the
`KI` namespace used by the handoff workbook.

### QL-001: WIP group is not release-qualified evidence

Entries in `i3c_ibi_wip` are enabled so they remain visible and runnable, but
the label records that the scenarios still require a clean native-source
regression/coverage qualification. An enabled entry is not itself evidence of
PASS or coverage closure.

### QL-002: Candidate qualification is pending

Repository checks performed during packaging do not replace a selected native RTL
compile, full regression, merged functional/assertion coverage report, or
verification-plan review. Until those artifacts are recorded in
`docs/release/RELEASE_MANIFEST.md`, the
package is a candidate rather than a qualified release.

No other test is intentionally hidden or waived in the current source plan.
Generated databases, logs, and reports are not tracked by Git.

## KI-002: Hot-join is unimplemented on the reviewed native RTL

- Classification: not implemented; the reviewed TT I3C RTL cannot enter the
  hot-join state, and no test in this environment claims hot-join coverage.
- RTL evidence (reviewed native source selected by the containing repository or
  `I3C_ROOT_DIR`):
  - `src/ctrl/controller_standby_i3c.sv:289` ties `hotjoin_done` to a constant
    `1'b0`.
  - `src/ctrl/i3c_target_fsm.sv:852-855` defines a `DoHotJoin` case arm that
    only handles exiting the state; no assignment anywhere in the file sets
    `state_d = DoHotJoin`, so the state is unreachable.
  - `src/ctrl/i3c_target_fsm.sv:183` documents this directly: "hot-join
    (currently not implemented)".
- Policy: hot-join is outside the IBI verification scope (see
  `docs/verification/VERIFICATION_PLAN.md`, Section 10) and no test targets
  it. This entry records the RTL limitation for handoff completeness; it
  does not require a test-plan change unless hot-join is brought into scope
  by a future revision.

## KI-003: IBI status-type coverage on the reviewed native RTL requires RTL-author confirmation

- Classification: unconfirmed — may be an intentional scope limitation of
  the reviewed Controller RTL, or an open gap. Not yet dispositioned.
- RTL evidence (reviewed native source selected by the containing repository or
  `I3C_ROOT_DIR`):
  - `src/i3c_pkg.sv:300-307` defines `ibi_stat_e` with five values:
    `RegularIBI`, `CreditACK`, `ScheduledCMD`, `AutocmdRead`,
    `StbyCRBcastCCC`.
  - `src/ctrl/flow_active.sv:1597` is the only assignment to
    `ibi_status_d.status_type` anywhere in the Controller RTL, and it always
    assigns `RegularIBI`. The other four values are never produced.
  - The adjacent line carries the RTL author's own open item:
    `src/ctrl/flow_active.sv:1599` — `// TODO: #95758 some IBIs require
    multiple IBI status desc according to HCI Spec`.
- Open question for the RTL author: are `CreditACK`/`ScheduledCMD`/
  `AutocmdRead`/`StbyCRBcastCCC` out of scope for this Controller by design,
  or does closing ticket #95758 change how `status_type` is assigned? The
  answer determines whether this is a documentation-only update to
  `docs/verification/VERIFICATION_PLAN.md` (record the four values as
  out-of-scope IBI classes) or a requirement gap to add to the requirement
  matrix once the RTL is updated.
- Policy: no test or coverage in this environment currently claims the four
  unproduced status-type values. Do not mark this closed until the RTL
  author responds.

## KI-004: Positive IBI without MDB is unsupported by the reviewed design path

- Classification: unsupported positive scenario on the reviewed Target and
  Controller paths; it is not waived measured behavior.
- RTL evidence is present in the reviewed native TT I3C source:
  - `src/ctrl/descriptor_ibi.sv:91-99` always transitions through `WriteMdb`
    and presents `data_mdb` as the first IBI byte, including the zero-payload
    case.
  - `src/ctrl/i3c_target_fsm.sv:236` describes the Target data state as sending
    IBI payload "including MDB"; there is no alternate no-MDB transmit state.
  - `src/ctrl/flow_active.sv:1624` rejects the Controller request when the
    matched DAT entry does not permit IBI payload (`~dat_rdata.ibi_payload`).
- Verification consequence: NACK with no transferred data is not positive
  no-MDB support. The focused Controller-RX reproduction
  `i3c_ibi_controller_rx_no_mdb_test` now sends an address-only IBI from
  a BCR[1]=1/BCR[2]=0 UVM Target and expects ACK from a matching, non-rejecting
  DAT entry even when `IBI_PAYLOAD=0`. It remains in the disabled
  `i3c_ibi_rtl_unsupported` group until the RTL/design disposition is recorded.
  `cp_mdb_present` remains unscored and the BCR no-MDB class is not claimed by
  normal coverage closure. Target-TX has no reviewed descriptor/programming
  contract for requesting a no-MDB IBI, so no synthetic DUT-Target case is
  added.

## Focused reproduction commands

Run commands from the package root after selecting the reviewed native source
root:

```bash
export CALIPTRA_ROOT=/absolute/path/to/caliptra-rtl
# Optional for a non-ancestor native source root:
# export I3C_ROOT_DIR=/absolute/path/to/tt-i3c-core
./run.sh doctor
```

Run the RTL-unsupported reproduction explicitly:

```bash
./run.sh regression --group i3c_ibi_rtl_unsupported --include-off
```

Run the enabled WIP group or the validated rechecks:

```bash
./run.sh regression --group i3c_ibi_wip
./run.sh regression --group i3c_ibi_validated_rechecks
```

A PASS from the unsupported test on a later RTL revision triggers review of
the RTL contract, test-plan classification, and verification plan. It does
not silently
change the current baseline.
