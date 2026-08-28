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

## External RTL

TT I3C RTL and recursive Caliptra RTL are not distributed in this package.
They are selected through `I3C_ROOT_DIR` and `CALIPTRA_ROOT`; exact reviewed
pins are in `i3c/sim/project/i3c_source_pins.mk`. Their licenses and notices
remain the responsibility of their source checkouts and the release owner.
