# I3C RAL Integration

`I3CCSR_uvm` is owned by the native I3C source resolved from the containing
repository, or by the optional integration root selected with `I3C_ROOT_DIR`.
The DV tree contributes only the AXI4-Lite adapter, predictor hookup, and
testbench integration.

`i3c_ral_model` wraps the generated leaf blocks in a 32-bit little-endian
UVM map at native CSR offsets. No verification-owned absolute base address,
window, or access-policy gate is applied.

`i3c_ral_all_regs_test` inventories generated registers and performs frontdoor
reads/reset checks where stable, plus write/read/restore checks on ordinary RW
fields. Registers with read/write side effects are reported as skipped.

The generated DAT and DCT memories remain attached at their native offsets.
They are not accessed by the current 32-bit frontdoor sequence; a dedicated
split-transaction memory sequence is required before enabling those accesses.

The passive RAL predictor updates the mirror from monitored AXI-Lite traffic,
while the generic CSR scoreboard checks modeled offsets independently.
