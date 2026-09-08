# Release Manifest

## Candidate identity

| Field | Value |
|---|---|
| Package | `tt_uvm_i3c` |
| Status | **CANDIDATE — NOT YET QUALIFIED** |
| Date | 2026-09-06 |
| Delivery branch | `vnchiplabs/uvm_i3c_ibi` |
| Delivery commit | To be recorded after packaging commit |
| Candidate source HEAD | `e17ca2b75dc12743ae7bc83185f03c969445aadc` (working tree changes below are not committed) |

## Source baseline

| Source | Required revision |
|---|---|
| Native TT I3C source root | Containing repository by default; optional `I3C_ROOT_DIR` override |
| Native Caliptra source root | Selected by `CALIPTRA_ROOT` (or its documented default) |
| UVM | Bundled 2020.3.1 |

Qualification must record the reviewed native source revision and use a clean
containing repository (or explicit `I3C_ROOT_DIR` override) containing
`src/i3c.f` and `src/csr/I3CCSR_uvm.sv`.

## Static inventory

| Item | Count/state |
|---|---:|
| Package test-class inventory | 41 (36 in-scope IBI tests, 3 supporting CSR/RAL tests, and 2 disabled RTL-defect reproductions) |
| Plan entries | 75 |
| Enabled / disabled entries | 73 / 2 |
| Enabled seed executions at plan defaults | 89 |
| Enabled IBI source inventory | 36 test classes / 70 active entries / 86 default seed executions (20 Target-TX classes / 44 cases; 16 Controller-RX classes / 26 cases) |
| Package assertion / IBI cover-property inventory | 39 IBI assertions total / 16 IBI cover properties |
| Functional coverage inventory | 6 covergroups / 16 documented objectives / 44 coverpoints / 14 crosses |
| Code coverage | Intentionally disabled for IBI-focused qualification |

### Customer IBI identity and matrix

The eight public customer scenarios are present in the authoritative plan:
four Target-TX cases (`addr_matrix`, `retry_limit`, `timing`, `content`),
three Controller-RX cases (`ordering`, `ack_nack`, `queue_pressure`), and
`i3c_ibi_multi_target_recovery_test`. Their internal implementations are
generic compatibility wrappers; the canonical engines and evidence are
mapped in Section 5.0 of the verification plan. The wrappers do not claim
additional address-layout variants, special timing variants, simultaneous
mixed policy, multi-source queue pressure, or live-arbitration recovery.

The current plan independently counts 36 active IBI classes, 70 active IBI
entries, and 86 default IBI executions. Of those 70 entries, 66 are directed
one-seed entries and four are random/stress entries with five plan seeds each:
`66 + (4 x 5) = 86`. The complete enabled plan adds three smoke/RAL entries for
89 executions. No seed policy was changed to obtain these counts.

An extended run using `--rand-num 10` would select ten seeds only for the four
`random-seed` entries, giving `66 + (4 x 10) = 106` planned executions. This is
runner/testplan arithmetic, not a PASS result from this workspace; qualification
evidence remains pending until an artifact is supplied.

## Qualification evidence

The release owner must replace each `PENDING` value after following
`docs/verification/QUALIFICATION.md`.

| Evidence | Result | Artifact or review reference |
|---|---|---|
| Package/self checks | PENDING | PENDING |
| Source/header inventory | STATIC PASS | `docs/release/audit/HEADER_AUDIT.md` |
| Native source doctor | PENDING | PENDING |
| Native compile | PENDING | PENDING |
| Full enabled regression | PENDING | PENDING |
| Assert/group coverage | PENDING | PENDING |
| Verification plan review | PENDING | PENDING |
| Known-issue disposition | PENDING | `docs/verification/KNOWN_ISSUES.md` |
| Release approval | PENDING | PENDING |

The reported historical `106/106` extended qualification and any coverage
percentages are not reproduced by the available artifacts in this checkout.
No VCS/URG executable or clean VDB set is present here, so compile, simulation,
SVA, scoreboard, and merged functional/assertion coverage remain `PENDING`.

Do not change status to qualified while any required item remains pending.
Generated logs, VDBs, and reports belong in an external artifact store, not in
the source release.
