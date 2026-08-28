# Delivery File and Header Audit

Audit date: 2026-08-20

This inventory describes the intended Git delivery after pending additions and
deletions are committed. Runtime output under `i3c/sim/out/`, generated input
under `i3c/sim/generated/`, and the removed UVM HTML documentation are excluded.

## Delivery inventory

| Area | Files | Header/licensing result |
|---|---:|---|
| Package root | 7 | Root `LICENSE`, `NOTICE`, entry-point README and changelog present |
| `docs/` | 13 | Centralized documentation; governed by the package license |
| `i3c/` root metadata | 2 | Ignore/attribute policy; detailed documentation is centralized |
| `i3c/rtl/` | 7 | All SystemVerilog has top-of-file SPDX and VNCHIP copyright |
| `i3c/sim/` | 49 | Runner/build sources; governed by root Apache-2.0 license |
| `i3c/verify/` | 177 | All 164 package SystemVerilog files have a top-of-file SPDX identifier |
| Bundled UVM | 192 | 174 upstream source files plus legal, README, deviations and compatibility material; HTML omitted |
| **Total** | **447** | Candidate source payload; generated/runtime artifacts excluded |

The total includes this audit document as part of the centralized `docs/` tree.

## SystemVerilog header results

| Source class | Files | SPDX at top | Copyright/provenance | Result |
|---|---:|---:|---|---|
| VNCHIP integration and UVM TB outside I3C VIP | 144 | 144 | 144 VNCHIP copyright and normalized author list | PASS |
| I3C VIP | 20 | 20 | 2 retained lowRISC copyrights; the other 18 identify CHIPS Alliance lineage through the TT fork, including 1 VNCHIP standalone packaging file | PASS |
| Bundled Accellera UVM source | 174 | Upstream format retained | 174 upstream copyright notices | PASS (third-party preserved) |

For third-party code, “PASS” means the upstream license/notice is present and
the source is attributable without inventing ownership. It does not require
rewriting upstream headers into the VNCHIP template.

Non-SystemVerilog implementation files are covered by the root Apache-2.0
license but are not yet uniformly normalized per file:

| Source class | Files | Per-file SPDX | Assessment |
|---|---:|---:|---|
| Shell runner files | 34 | 0 | Package-license compliant; WARNING if customer policy mandates per-file SPDX |
| Make/Makefile inputs | 9 | 1 | Package-license compliant; WARNING if customer policy mandates per-file SPDX |

Therefore the SystemVerilog handoff is fully header-normalized. A stricter
policy requiring SPDX on every executable/build file would require a separate
mechanical pass over the shell and Make sources.

## Approved header samples

Inherited I3C VIP file:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Derived from the CHIPS Alliance I3C UVM VIP and vendored through
// the Tenstorrent tt-i3c-core fork.
```

VNCHIP-created standalone source:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 VNCHIP LABS
// Authors: Huynh Pham Anh Duy, Thai Hai Dang
// Standalone packaging derived from timing definitions in the CHIPS Alliance
// I3C UVM VIP as carried by the Tenstorrent tt-i3c-core fork.
```

Do not add a VNCHIP copyright line to an inherited file merely because it was
packaged or reformatted. Record meaningful local changes in provenance and Git.

## Date policy

- SPDX identifiers do not contain a date.
- A copyright header normally uses the year of first creation/publication,
  for example `Copyright (c) 2026 VNCHIP LABS`.
- Use a year range only when the release owner requires it and meaningful
  development spans multiple calendar years, for example `2026-2027`.
- If a project template contains a separate `Date` field, use ISO 8601
  `YYYY-MM-DD` and record the original creation date. Do not rewrite that field
  for every modification; Git history is the modification record.
- Do not invent a date or copyright owner for inherited third-party files.
- Release documents use the candidate/release publication date, independently
  of individual source creation dates.
