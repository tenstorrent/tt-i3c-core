# Changelog

This changelog records significant package-level verification changes. Git
history remains the authoritative source for detailed commit-level changes.

The development milestones below describe the resulting package capability,
not every intermediate debug or implementation change.

## 2026-09-05 — Customer IBI Regression Restoration

### Added

- Restored the eight public customer testcase identities as generic
  compatibility wrappers. They preserve historical test/result-database names
  while delegating stimulus and checking to canonical Target-TX and
  Controller-RX engines; they are not independent signoff claims.
- Reused the native multi-requester arbitration, HCI/DAT, FIFO/IRQ, scoreboard,
  SVA, and coverage infrastructure. The restored entries are directed, one
  seed each, and remain `Pending` until native qualification evidence exists.
- Renamed the prior local controller-prefixed recovery implementation to the
  exact public contract `i3c_ibi_multi_target_recovery_test` while retaining
  its canonical multi-target followed by recovery-cleanup sequence.

## 2026-07-02 to 2026-07-20 — Initial Verification Environment

### Added

- Established the UVM environment and the initial SVA and functional-coverage
  framework for the peripherals verification context.
- Integrated the native TT I3C RTL from the containing repository and its
  recursive Caliptra dependency without copying either RTL source tree into
  this package.
- Added source-root selection, revision checking, and the initial reviewed-
  source contract used by compile and simulation flows.
- Integrated the AXI4-Lite VIP as the CSR/HCI frontdoor and added the initial
  I3C bus VIP connection.
- Integrated the generated `I3CCSR_uvm` model supplied by the containing native
  source. The package provides a generic AXI4-Lite adapter, helper services,
  and passive predictor; it does not own the generated leaf register model.
- Adapted the generated RAL hierarchy to a 32-bit little-endian AXI4-Lite root
  map while retaining the generated I3C subblocks and DAT/DCT submaps.
- Added CSR smoke and all-register audit flows, a reusable CSR scoreboard, and
  passive prediction from monitored AXI4-Lite traffic.
- Established VCS compile/test execution, Slurm dispatch, result summaries,
  waveform support, and basic source/tool diagnostics.

## 2026-07-21 to 2026-08-19 — Target-TX IBI Verification

### Added

- Added the DUT-Target IBI transmit flow with bus priming, host response, and
  passive transaction correlation.
- Added directed ACK and NACK scenarios, MDB and payload checking, invalid or
  disabled target handling, busy-bus behavior, and FIFO/IRQ observation.
- Added retry and retry-exhaustion scenarios, including terminal-state,
  interrupt-pending, descriptor-preservation, and recovery checks.
- Added Target-TX arbitration scenarios for DUT win, DUT loss, retry, partial
  observation, recovery cleanup, and competing requesters.
- Extended the IBI scoreboard and observers to correlate the expected request,
  bus result, HCI/CSR state, IRQ state, and terminal completion outcome.

## 2026-07-24 to 2026-08-19 — Controller-RX IBI Verification

### Added

- Added the DUT-Controller IBI receive flow and active Controller response to a
  Target-generated IBI request.
- Added Controller-RX content, MDB decode, ACK/NACK policy, timing-context,
  pending-read notification, queue overflow, queue reset/flush, FIFO, and IRQ
  scenarios.
- Added HCI response-descriptor and IBI queue handling with explicit cleanup of
  interrupt and queue state between scenarios.
- Added passive Controller-RX observation and scoreboard correlation across bus
  content, HCI response data, queue state, and interrupt state.
- Improved event synchronization so START, ACK, completion, queue, IRQ, reset,
  and recovery evidence is sampled deterministically.
- Added canonical Controller-RX multi-target ordering/arbitration, policy,
  FIFO/IRQ, and subsequent recovery-cleanup checks.

## 2026-08-07 to 2026-08-19 — Stress, Recovery, and Multi-Target

### Added

- Added constrained-random Target-TX IBI plans with validity checks that reject
  unsupported or internally inconsistent generated cases.
- Added plan-controlled multi-seed execution for entries tagged as random;
  directed entries retain their declared fixed seed policy.
- Added stress scenarios spanning payload classes, ACK/NACK outcomes, retry,
  recovery, queue/IRQ behavior, and repeated IBI activity.
- Added reset, queue-flush, partial-observation, retry-exhaustion, and terminal
  cleanup scenarios.
- Expanded the environment to four simultaneous IBI requester slots and added
  directed four-requester and grouped multi-target arbitration scenarios.
- Added loser-release, single-owner, DUT-win/DUT-loss, and ordering checks for
  multi-target arbitration; recovery cleanup remains a subsequent canonical
  scenario rather than live-arbitration injection.

## 2026-07-02 to 2026-08-19 — SVA, Coverage, and Verification Closure

### Added

- Added passive I3C/IBI protocol assertions and role-specific Target-TX and
  Controller-RX assertions.
- Added assertions and cover properties for request/completion sequencing,
  ACK/NACK response, arbitration, payload/MDB handling, queue/IRQ behavior,
  retry, reset, and recovery events supported by current observability.
- Added synchronized normalized events connecting the UVM observers,
  scoreboards, functional coverage, and SVA checkers.
- Added role-specific after-normal-transfer evidence: Controller timing-context
  checks and Target STOP-to-START/`T_AVAL` checks now feed a shared assertion
  and separate Target/Controller cover properties.
- Added canonical IBI functional covergroups for attempt, completion, protocol
  content, arbitration/recovery, and queue/IRQ behavior.
- Added requirement-to-test, requirement-to-SVA, and requirement-to-coverage
  mapping in the Verdi HVP.
- Restricted the scored closure database to requirement-owned IBI assertion and
  functional-group coverage. Generic AXI/CSR boundary and non-IBI objects are
  not included in the IBI qualification denominator.
- Removed unreachable or unsupported bins from the claimed IBI model where the
  reviewed native architecture cannot produce the represented state. This is scope
  alignment, not a waiver of reachable IBI behavior.
- Added coverage collection and merge support with source/case provenance and
  checks for required coverage sampling.

### Qualification status

- The authoritative candidate inventory is maintained in
  `docs/release/RELEASE_MANIFEST.md`.
- Documented accepted IBI without MDB as unsupported by the reviewed native
  Target/Controller RTL paths; it remains outside measured closure rather than
  being waived or synthetically stimulated.
- Code coverage is intentionally outside the IBI-focused qualification target;
  the required scored metrics are assertion and functional-group coverage.
- Final reviewed-source regression, merged coverage, and HVP review evidence are
  still pending and must not be represented as completed signoff.

## 2026-07-17 to 2026-08-20 — Regression and Automation Infrastructure

### Added

- Added local and Slurm-backed VCS execution with parallel burst scheduling.
- Added case-aware test-plan entries, per-entry plusargs, compile requirements,
  groups, enable state, seed policy, and plan-controlled random seed expansion.
- Added scheduler/attempt/seed retry handling while preserving the complete
  attempt history and preventing verification failures from being silently
  reclassified as infrastructure passes.
- Added live PLAN/START/PASS/FAIL status, compact terminal output, persistent
  per-case logs, command-execution summaries, and failure classification.
- Added paginated test discovery and copyable test, case, and plusarg listings.
- Added VCD, VPD, and FSDB generation and viewing flows, with dump artifacts
  isolated by run and case.
- Added per-test coverage collection, parallel coverage merge, IBI-only metric
  selection, coverage summaries, and artifact indexing.
- Added regression summaries carrying test, case, seed, plusargs, return code,
  UVM warning/error/fatal counts, SVA errors, logs, and retry provenance.
- Added a fail-only summary view that reports each final failed test together
  with its simulation-log path, plus command-specific summary help.
- Changed the default summary view into a compact multi-run index with four
  stable artifact paths per Run ID; detailed file content remains opt-in.
- Added the actual compile-log path to every regression, coverage, and
  single-test result while keeping runtime metrics and detail-log links in one
  compact result block.
- Rendered test-list plusargs as a directly reusable `--plusargs "..."`
  command fragment instead of a display-only `P='...'` field.
- Made reported artifact paths relative to the public package root so commands
  run from `./run.sh` resolve `i3c/sim/out/...` links without exposing an
  internal or developer-specific absolute path.
- Aligned single-test case records with regression reporting while omitting
  burst and retry-only fields, and added dump status, format, and file
  provenance to regression and coverage case records.
- Added a dependency-free per-run HTML summary with PASS/FAIL filtering and
  relative links to available simulation logs, compile logs, and waveform
  dumps; HTML generation remains non-verdict-affecting.

## 2026-08-20 — Standalone Handoff Candidate

### Added

- Prepared `tt_uvm_i3c` as a standalone IBI-focused UVM delivery with a public
  package-root `run.sh` entry point.
- Added explicit reviewed, latest, and reviewed-worktree source policies. The
  reviewed policy requires recorded TT I3C and Caliptra revisions and clean
  source state for qualification evidence.
- Added standalone source checks, package self-checks, compile/regression/
  coverage qualification instructions, and release-manifest requirements.
- Bundled the UVM 2020.3.1 fallback while consuming TT I3C RTL from the
  containing repository and retaining Caliptra as a documented dependency.
- Added third-party provenance, SPDX/header audit, LICENSE and NOTICE material,
  architecture and source-baseline documents, release notes, known-issue
  disposition, qualification procedure, and release manifest.
- Removed generated upstream UVM HTML documentation from the delivery payload;
  no UVM runtime source behavior was modified.
- Synchronized the current environment, VIP, RAL integration, tests,
  sequences, scoreboards, SVA, functional coverage, HVP, test plan, and runner
  into the standalone package layout.

### Changed

- The earlier handoff retained legacy source-lineage names for compatibility.
  The current active package has generic I3C namespaces and no runtime
  dependency on the retired integration tree.
- Standardized VNCHIP authorship and third-party provenance without claiming
  ownership of upstream UVM, I3C VIP, or generated I3C RAL sources.

## Historical Handoff Baseline

The following table records the 2026-08-20 handoff snapshot. Its branch and
standalone-source revision are historical provenance, not the identity of the
current candidate checkout. For the active candidate branch, source HEAD, and
qualification state, see [the release manifest](docs/release/RELEASE_MANIFEST.md).

| Field | Baseline |
|---|---|
| Handoff date | 2026-08-20 |
| Package | `tt_uvm_i3c` |
| Status | **Candidate — not yet qualified** |
| Historical UVM branch | `feature/uvm_i3c_cleanup` |
| Historical standalone source baseline commit | `f50e0adbd02fbd1148a5eb6ba136082980ca0912` |
| Final delivery commit/tag | **PENDING release packaging and approval** |
| Native TT I3C source root | Containing repository by default; optional `I3C_ROOT_DIR` override |
| Native Caliptra source root | Selected by `CALIPTRA_ROOT` |
| UVM library | Bundled UVM 2020.3.1 fallback |
| Coverage scope | IBI assertion and functional-group coverage; code coverage excluded |
| Qualification evidence | Native compile, full enabled regression, merged assert/group coverage, and verification-plan review **PENDING** |

The machine-readable native compile authority is `${I3C_ROOT_DIR}/src/i3c.f`,
with the recursive Caliptra dependency selected by `CALIPTRA_ROOT`. The release
owner must update `docs/release/RELEASE_MANIFEST.md` with immutable artifacts
and approval before this candidate is described as qualified.

## Known Limitations

- Verification and coverage claims are limited to the IBI requirements mapped
  by `docs/verification/VERIFICATION_PLAN.md`; this package does not claim
  full I3C protocol or full-core functional coverage.
- The Controller HCI `SOFT_RST` self-clear reproduction is disabled because the
  reviewed RTL does not implement the tested self-clearing behavior.
- The generated DAT and DCT memories are inventoried but are not frontdoor
  tested. Their 64/128-bit entries require a dedicated split-transaction
  sequence over the current 32-bit AXI4-Lite adapter.
- No-MDB IBI behavior is outside the current reviewed design contract; the
  documented IBI path requires an MDB and the unsupported state is not claimed
  as covered.
- The delivered execution flow currently targets Synopsys VCS. Final release
  qualification evidence for the selected VCS version is still pending; other
  simulators and tool versions are not claimed until separately validated.
- The candidate has not completed the native-source qualification procedure;
  passing test and coverage percentages must be taken from the final immutable
  qualification artifacts rather than inferred from the static inventory.
