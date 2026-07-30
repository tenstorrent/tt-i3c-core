# I3C VIP

This directory is the self-contained I3C protocol VIP used by the standalone
TT UVM I3C verification environment.

The initial backend was vendored from
`tenstorrent/tt-i3c-core/verification/uvm_i3c/dv_i3c`, which is a fork of
`chipsalliance/i3c-core`. The initial vendored revision is:

```text
ff1626f356a948f0512739ddd1103cf385cb0ed7
```

The latest TT `tt/main` revision reviewed for VIP provenance is:

```text
a6361105cd3432699da636f1f5e6f1eb4df09ed2
```

The upstream `verification/uvm_i3c/dv_i3c` implementation and root Apache
license are unchanged between those two revisions. The standalone VIP
therefore remains based on the same upstream implementation while recording
the latest provenance check. The package RTL qualification pin has separately
advanced to the reviewed `a636110` revision in
`i3c/sim/project/i3c_source_pins.mk`; this does not re-vendor or alter the VIP.

The backend remains under Apache License 2.0. Existing upstream source headers
are retained verbatim. Files that did not carry an upstream header remain
without an added source header. SMC-specific adapters and checking remain in
the parent testbench integration layer.

## Standalone integration changes

The following changes were made after the initial vendor operation:

| File | Change |
|---|---|
| `core/i3c_vip_types_pkg.sv` | Added a dependency-light package for timing types used by the interface |
| `i3c_vip_pkg.sv` | Imports the shared timing types instead of declaring duplicate structures |
| `if/i3c_if.sv` | Imports the timing package and includes the UVM/DV macro definitions required for standalone compilation |
| `i3c_vip.mk` | Compiles the timing package before the interface and main VIP package |
| `sequences/i3c_broadcast_followed_by_data_with_rstart_seq.sv` | Rewrites the transaction loop into an LRM-compatible form without changing the intended transfer sequence |

These are standalone packaging and compatibility changes. They do not claim
ownership of the upstream I3C protocol implementation.

## License and attribution

- `LICENSE` contains the complete Apache License 2.0 text from the reviewed TT
  core.
- The package-level `NOTICE` records the TT, CHIPS Alliance, and
  lowRISC/OpenTitan provenance.
- Existing lowRISC/OpenTitan copyright and SPDX headers remain unchanged.

## Compile contract

Compile in this order:

1. `core/i3c_vip_types_pkg.sv`
2. `if/i3c_if.sv`
3. `i3c_vip_pkg.sv`

Include `i3c_vip.mk` to obtain `I3C_VIP_INCDIRS` and
`I3C_VIP_SRC_FILES`.

The public class and interface names are intentionally retained for test
compatibility. Users import `i3c_vip_pkg::*`.
