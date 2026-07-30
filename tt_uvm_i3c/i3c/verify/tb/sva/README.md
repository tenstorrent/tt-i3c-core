# SMC Peripherals SVA

The active integration checkers are instantiated in
`tb_smc_peripherals_top.sv`; they do not modify the I3C RTL.

- `smc_i3c_boundary_sva`: AXI/HCI boundary handshake and denied-access checks.
- `smc_i3c_ibi_bus_sva`: role-independent bus integrity, bounded-frame and IRQ
  sanity checks for IBI tests.
- `smc_i3c_ibi_target_sva`: DUT-Target header, response-turnaround and
  NACK-stop checks.
- `smc_i3c_ibi_controller_sva`: DUT-Controller header, ACK/NACK and legal-stop
  checks.
- `smc_i3c_ibi_protocol_sva`: portable normalized-event checks for enable and
  address eligibility, retry/arbitration context, content, DAT policy,
  queue/IRQ commit, overflow/recovery, and legal timing entry.

Functional coverage and scoreboards remain responsible for scenario closure
and end-to-end data/HCI-record comparison. Planned assertions that require
internal FIFO/status observations remain listed in the verification workbook
until a stable non-RTL probe interface is approved.
