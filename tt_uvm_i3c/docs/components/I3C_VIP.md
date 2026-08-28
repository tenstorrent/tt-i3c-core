# I3C VIP

This directory is the self-contained I3C protocol VIP used by the
`smc_peripherals` verification environment.

The backend originates from the CHIPS Alliance I3C UVM environment, including
development by Antmicro contributors. This package vendored it through
`tenstorrent/tt-i3c-core/verification/uvm_i3c/dv_i3c`. The initial vendored
TT revision is:

```text
ff1626f356a948f0512739ddd1103cf385cb0ed7
```

The latest reviewed TT source used for this standalone integration is commit
`a6361105cd3432699da636f1f5e6f1eb4df09ed2`. The authoritative RTL and
Caliptra qualification pins remain in `i3c/sim/project/i3c_source_pins.mk`.

The backend remains under Apache License 2.0. Existing upstream source headers
are retained where present. The standalone copy contains packaging changes and
targeted integration fixes; it must not be represented as a byte-identical
copy of either revision. See `docs/THIRD_PARTY.md` for the audited
provenance, modified-file inventory, and redistribution material.

## Compile contract

Compile in this order:

1. `core/i3c_vip_types_pkg.sv`
2. `if/i3c_if.sv`
3. `i3c_vip_pkg.sv`

Include `i3c_vip.mk` to obtain `I3C_VIP_INCDIRS` and
`I3C_VIP_SRC_FILES`.

The public class and interface names are intentionally retained for test
compatibility. Users import `i3c_vip_pkg::*`.

## Local integration modifications

Scenario policy remains in the parent testbench adapters. For deterministic
multi-Target Controller-RX synchronization, `i3c_if.wait_for_host_start()` has
an optional Device-driver observation qualifier and exposes
`device_driver_wait_for_start_active`. Only the Device driver's `DrvIdle` call
enables it; monitor and Host callers retain the default disabled qualifier.

The flag is observation-only: it does not drive SCL/SDA, add delay, alter the
VIP state transition, or create a functional-coverage/SVA metric. The SMC
multi-Target vseq uses it solely to defer HCI command issue until every Device
driver is actually blocked waiting for Controller START. The driver and
interface contain local modification markers at behavioral changes.
Packaging-only adaptations are inventoried in `docs/THIRD_PARTY.md`.

Apache License 2.0 permits modification and redistribution subject to its
conditions. Preserve this directory's `LICENSE`, upstream attribution and any
applicable NOTICE material, retain relevant copyright/patent/trademark notices,
and mark modified files. This paragraph records engineering provenance and is
not legal advice; release owners remain responsible for compliance review.
