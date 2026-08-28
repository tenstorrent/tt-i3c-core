# SMC I3C RAL Integration

`I3CCSR_uvm` remains owned by the selected upstream I3C checkout. OCAH compiles
that generated package through `I3C_ROOT_DIR` and owns only the AXI-Lite
adapter, predictor hookup, test policy, and parent-environment integration.

`smc_i3c_ral_model` is the OCAH compatibility root. It reuses the generated
leaf blocks unchanged but replaces the upstream 16-byte `UVM_NO_ENDIAN` root
with a 4-byte little-endian map matching the OCAH AXI4-Lite frontdoor. This
prevents map translation and false address-overlap errors during `lock_model()`.

`smc_i3c_ral_all_regs_test` inventories every generated register. It performs
frontdoor reads and reset checks where reads are stable, then two-pattern
write/read/restore checks on nonvolatile RW fields. Registers with read or
write side effects (reset, command/data ports, interrupt force/status,
recovery, and other active-control paths) are counted and reported as skipped.

The generated DAT and DCT memories are inventoried but not accessed by this
test. Their entries are 64/128-bit while the current OCAH frontdoor adapter is
32-bit. Their submaps remain attached at `0x400` and `0x800` so they inherit
the root endianness, but a dedicated split-transaction memory sequence is
still required before frontdoor memory accesses are enabled.

The passive RAL predictor updates the mirror from monitored AXI-Lite traffic.
The existing CSR scoreboard remains connected independently, so modeled
transactions are checked outside the initiating virtual sequence as well.
