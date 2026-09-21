# Delivery File and Header Audit

Audit date: 2026-09-07

Source revision: `e17ca2b75dc12743ae7bc83185f03c969445aadc`

This inventory counts regular files in the current source tree. Package-root
files are counted at depth one; `docs/`, `i3c/verify/`, and `third_party/` are
counted recursively. `i3c/sim/out/` and `i3c/sim/generated/` are excluded as
runtime/generated content. The local forensic reference directory
`docs/tt_uvm_i3c_original/` is excluded, as is Git metadata. The empty
`i3c/rtl/` placeholder is counted, but its SystemVerilog source count is
reported separately because native RTL is consumed from the containing
repository.

## Delivery inventory

| Area | Files | Header/licensing result |
|---|---:|---|
| Package root | 7 | Root `LICENSE`, `NOTICE`, entry-point README and changelog present |
| `docs/` | 13 | Centralized documentation; governed by the package license |
| `i3c/` root metadata | 2 | Ignore/attribute policy; detailed documentation is centralized |
| `i3c/rtl/` | 1 | `.gitkeep` only; **0 SystemVerilog RTL files** because native RTL is consumed from the containing repository |
| `i3c/sim/` | 39 | Runner/build sources; generated/runtime directories excluded; governed by root Apache-2.0 license |
| `i3c/verify/` | 170 | 136 package SystemVerilog/header files outside the I3C VIP plus 19 I3C VIP files; all have top-of-file SPDX identifiers |
| Bundled UVM | 192 | 181 upstream source files under `src/`, 4 compatibility source files, and 7 package/legal/readme files; generated HTML omitted |
| **Total** | **424** | Current source payload; generated/runtime/forensic reference artifacts excluded |

The total includes this audit document as part of the centralized `docs/` tree.

## SystemVerilog header results

| Source class | Files | SPDX at top | Copyright/provenance | Result |
|---|---:|---:|---|---|
| VNCHIP integration and UVM TB outside I3C VIP | 136 | 136 | 136 VNCHIP copyright and normalized author list | PASS |
| I3C VIP | 19 | 19 | 2 retained lowRISC copyrights; the other 17 identify CHIPS Alliance lineage through the TT fork, including 1 VNCHIP standalone packaging file | PASS |
| Bundled Accellera UVM source | 181 | Upstream format retained | 181 upstream copyright notices | PASS (third-party preserved) |

For third-party code, “PASS” means the upstream license/notice is present and
the source is attributable without inventing ownership. It does not require
rewriting upstream headers into the VNCHIP template.

Non-SystemVerilog implementation files are covered by the root Apache-2.0
license but are not yet uniformly normalized per file:

| Source class | Files | Per-file SPDX | Assessment |
|---|---:|---:|---|
| Shell runner files | 30 | 0 | Package-license compliant; WARNING if customer policy mandates per-file SPDX |
| Make/Makefile inputs | 8 | 1 | Package-license compliant; WARNING if customer policy mandates per-file SPDX |

VNCHIP-owned SystemVerilog sources use the full package header template shown
below. Inherited I3C VIP sources retain their upstream/provenance headers rather
than receiving a new VNCHIP copyright block. A stricter policy requiring SPDX
on every executable/build file would require a separate mechanical pass over
the shell and Make sources.

## Approved header samples

Inherited I3C VIP file:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Derived from the CHIPS Alliance I3C UVM VIP and vendored through
// the Tenstorrent tt-i3c-core fork.
```

VNCHIP-created standalone source:

```systemverilog
// *****************************************************************************
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 VNCHIP LABS
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// File        : i3c_vip_types_pkg.sv
// Description : Standalone I3C VIP timing types derived from the Tenstorrent tt-i3c-core fork.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-09-08
//
// *****************************************************************************
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
