# Qualification Procedure

This procedure defines the minimum evidence needed to promote the candidate to
a qualified release. Run from the package root on the intended server/tool
environment.

## 1. Select and record native sources

```bash
export CALIPTRA_ROOT=/absolute/path/to/caliptra-rtl
./run.sh doctor
```

The runner resolves `I3C_ROOT_DIR` by walking upward to the containing
repository with `src/i3c.f`. Set it explicitly only for a non-ancestor
integration layout. Record the resolved native and Caliptra source revisions,
clean-state checks, simulator version, and UVM selection.

## 2. Regenerate and inspect the plan

```bash
./run.sh generate
./run.sh list-tests --all
```

Compare the generated entries, enable state, per-entry plusargs, and seed
policy against the authoritative inventory in the release manifest. The
disabled SOFT_RST reproduction must not enter the normal regression silently.

The customer matrix arithmetic is observable in the generated plan: 70 active
IBI entries contain 66 directed one-seed entries and four entries tagged
`random-seed`, each with five default seeds, so `66 + (4 x 5) = 86` planned
IBI executions. The three enabled smoke/RAL rows bring the full enabled plan
to 89 executions. `--rand-num 10` replaces seeds only on those four tagged
rows, producing `66 + (4 x 10) = 106` planned executions; it does not change
the directed entries. This arithmetic must not be reported as 106 PASS without
the corresponding run artifacts.

For the customer IBI restoration, preserve a raw pre-change snapshot before
generation (`./run.sh list-tests --all --format raw >
/tmp/i3c_ibi_inventory_before_restore.txt`). The restored directed entries are
`i3c_ibi_target_tx_multi_target_addr_matrix_test`,
`i3c_ibi_target_tx_retry_limit_test` (the truthful single-requester retry-limit
identity),
`i3c_ibi_target_tx_multi_target_timing_test`,
`i3c_ibi_target_tx_multi_target_content_test`,
`i3c_ibi_controller_rx_multi_target_ordering_test`,
`i3c_ibi_controller_rx_multi_target_ack_nack_test`,
`i3c_ibi_controller_rx_multi_target_queue_pressure_test`, and
`i3c_ibi_multi_target_recovery_test`. Compare the generated inventory to the
snapshot and confirm that every pre-existing row keeps its case ID, enabled
state, seed policy and plusargs.

## 3. Compile and run enabled tests

```bash
./run.sh compile
./run.sh regression --all
```

All enabled cases and required seeds must produce an explicit PASS verdict.
Scheduler/infrastructure retries are acceptable only when the final artifact
preserves their history and no verification failure is reclassified as PASS.

## 4. Collect IBI coverage

```bash
./run.sh coverage --all
```

Review assertion and functional-group coverage, unresolved objects, zero-hit
bins/properties, exclusions, and merge provenance. Code coverage is outside the
current IBI-focused qualification target and must not be included in the
denominator accidentally.

## 5. Review the verification plan

Walk `docs/verification/VERIFICATION_PLAN.md` requirement by requirement
against the merged coverage result. Confirm every mapped test, SVA, and
functional-coverage object resolves against this candidate, update each
requirement's `Status` from `Pending` to `Measured` only where recorded
evidence supports it, and confirm that `Not Applicable` and `Out of Scope`
entries do not contribute false closure.

## 6. Record and approve

Update `docs/release/RELEASE_MANIFEST.md` with immutable artifact references, results,
tool/source versions, review owner/date, and the final delivery commit. Resolve
or explicitly disposition every item in `docs/verification/KNOWN_ISSUES.md`. Only then may
the manifest status move from candidate to qualified.
