# Third-Party Software and Provenance

This inventory supports engineering and release review; it is not legal advice.

## Accellera UVM 2020.3.1

- Location: `third_party/uvm-core-2020.3.1/`
- Upstream: Accellera UVM reference implementation.
- License: Apache License 2.0 (`LICENSE.txt`).
- Notices: `NOTICE.txt` is included with the bundled source.
- Role: default UVM implementation; `DV_UVM_HOME` may select a qualified
  compatible external UVM.
- Packaging: generated upstream HTML documentation is intentionally omitted;
  it is not needed for compile or simulation. Source, license, notice, README,
  deviations, and compatibility material are retained.

## I3C protocol VIP

- Location: `i3c/verify/vip/i3c_vip/`
- Lineage: CHIPS Alliance I3C UVM VIP, including development by Antmicro
  contributors; delivered to this package through the Tenstorrent
  `tt-i3c-core` fork.
- Initial vendored TT revision:
  `ff1626f356a948f0512739ddd1103cf385cb0ed7`.
- Latest reviewed TT integration/source revision:
  `a6361105cd3432699da636f1f5e6f1eb4df09ed2`.
- License: Apache License 2.0; the directory includes `LICENSE`.

Audited standalone differences include:

- added `core/i3c_vip_types_pkg.sv` for shared timing types;
- package/interface/makefile compile-order adaptations;
- a loop-control rewrite in
  `sequences/i3c_broadcast_followed_by_data_with_rstart_seq.sv`;
- deterministic Device-driver START observation in `if/i3c_if.sv` and
  `agent/i3c_driver.sv` for multi-target Controller-RX synchronization.

Many other sequence-file hash differences are newline normalization only.
Behaviorally modified driver/interface locations retain local modification
comments; this inventory records packaging-only changes that do not naturally
carry a source marker. Preserve upstream headers, the VIP license, this
provenance record, and applicable package notices when redistributing.

The inherited VIP revision did not provide a per-file copyright/SPDX header on
the files audited here. The standalone package adds
`SPDX-License-Identifier: Apache-2.0` plus a derived-from provenance line to 17
inherited files; this identifies the governing license without inventing an
upstream copyright owner. The standalone `i3c_vip_types_pkg.sv` carries both
VNCHIP packaging ownership and its CHIPS Alliance lineage through the TT fork.
Existing
lowRISC/OpenTitan headers are unchanged.

## Native RTL and dependencies

TT I3C RTL is consumed from the containing repository and recursive Caliptra
RTL is resolved as a dependency; neither source tree is distributed in this
package. The runner resolves the native TT I3C source from the containing
repository's `src/i3c.f`; `I3C_ROOT_DIR` is only an override for a non-ancestor
integration layout. `CALIPTRA_ROOT` selects the recursive dependency when it is
not at the documented default. The native `src/i3c.f` is the compile authority.
Their licenses and notices remain the responsibility of the source trees and
the release owner.
