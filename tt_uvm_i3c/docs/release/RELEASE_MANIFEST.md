# Release Manifest

## Candidate identity

| Field | Value |
|---|---|
| Package | `tt_uvm_i3c` |
| Status | **CANDIDATE — NOT YET QUALIFIED** |
| Date | 2026-08-20 |
| Delivery branch | `feature/tt_uvm_i3c` |
| Delivery commit | To be recorded after packaging commit |

## Source baseline

| Source | Required revision |
|---|---|
| TT I3C branch | `tt/main` |
| TT I3C commit | `a6361105cd3432699da636f1f5e6f1eb4df09ed2` |
| Caliptra commit | `a4582f5856136286d2389b1cfa8de2910a82fe5e` |
| UVM | Bundled 2020.3.1 |

The machine-readable authority is
`i3c/sim/project/i3c_source_pins.mk`. Qualification must use
`SOURCE_MODE=pinned` and a clean source checkout.

## Static inventory

| Item | Count/state |
|---|---:|
| Package test-class inventory | 41 (36 in-scope IBI tests, 3 supporting CSR/RAL tests, and 2 disabled RTL-defect reproductions) |
| Plan entries | 75 |
| Enabled / disabled entries | 73 / 2 |
| Enabled seed executions at plan defaults | 89 |
| Enabled IBI source inventory | 36 test classes / 70 unique case IDs (20 Target-TX classes / 44 cases; 16 Controller-RX + shared classes / 26 cases) |
| Package assertion / IBI cover-property inventory | 46 assertions total (39 IBI + 7 non-IBI boundary) / 16 IBI cover properties |
| Functional coverage inventory | 6 covergroups / 16 documented objectives / 44 coverpoints / 14 crosses |
| Code coverage | Intentionally disabled for IBI-focused qualification |

## Qualification evidence

The release owner must replace each `PENDING` value after following
`docs/verification/QUALIFICATION.md`.

| Evidence | Result | Artifact or review reference |
|---|---|---|
| Package/self checks | PENDING | PENDING |
| Source/header inventory | STATIC PASS | `docs/release/audit/HEADER_AUDIT.md` |
| Pinned source doctor | PENDING | PENDING |
| Pinned compile | PENDING | PENDING |
| Full enabled regression | PENDING | PENDING |
| Assert/group coverage | PENDING | PENDING |
| Verification plan review | PENDING | PENDING |
| Known-issue disposition | PENDING | `docs/verification/KNOWN_ISSUES.md` |
| Release approval | PENDING | PENDING |

Do not change status to qualified while any required item remains pending.
Generated logs, VDBs, and reports belong in an external artifact store, not in
the source release.
