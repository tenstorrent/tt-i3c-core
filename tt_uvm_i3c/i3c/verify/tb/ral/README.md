# TT I3C RAL Integration

`I3CCSR_uvm` remains owned by the selected upstream I3C checkout. The
standalone environment compiles that generated package through `I3C_ROOT_DIR`
and owns only the AXI4-Lite adapter, predictor hookup, and test policy.

`smc_i3c_ral_model` is the compatibility root retained from the integration
baseline. It reuses the generated leaf blocks unchanged but replaces the
upstream 16-byte `UVM_NO_ENDIAN` root with a 4-byte little-endian map matching
the bundled AXI4-Lite frontdoor.

`smc_i3c_ral_all_regs_test` inventories generated registers and performs safe
reset/read/write/restore checks. Registers with side effects are reported as
skipped rather than accessed destructively.

DAT and DCT entries are 64/128-bit while the current frontdoor is 32-bit. They
remain inventoried but require a dedicated split-transaction sequence before
frontdoor memory accesses are enabled.

The passive RAL predictor and CSR scoreboard remain independent checking
paths; neither replaces the IBI protocol scoreboard.
