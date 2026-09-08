# I3C VIP

This directory contains the self-contained I3C protocol VIP used by the
native I3C verification environment. Public protocol names, including
`i3c_if`, are retained for compatibility with the upstream VIP.

The backend originates from the CHIPS Alliance I3C UVM environment, including
Antmicro contributions, and is redistributed under Apache License 2.0. The
source package includes targeted integration changes documented in
`docs/THIRD_PARTY.md`.

## Compile contract

Compile the VIP in this order:

1. `core/i3c_vip_types_pkg.sv`
2. `if/i3c_if.sv`
3. `i3c_vip_pkg.sv`

Include `i3c_vip.mk` to obtain the include directories and source list.

## Local integration modifications

For deterministic multi-Target Controller-RX synchronization,
`i3c_if.wait_for_host_start()` has an optional Device-driver observation
qualifier and exposes `device_driver_wait_for_start_active`. The flag is
observation-only: it does not drive SCL/SDA or alter VIP timing/state
transitions. The DV-specific monitor and driver subclasses keep these changes
outside the protocol VIP API.

Preserve this directory's `LICENSE`, upstream attribution, and applicable
notice material when redistributing the package.
