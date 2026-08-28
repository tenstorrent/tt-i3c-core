// *****************************************************************************
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 VNCHIP LABS
// Authors: Huynh Pham Anh Duy, Thai Hai Dang
//
// File        : smc_i3c_ibi_target_tx_dut_win_test.sv
// Description : DUT-Target wins real IBI arbitration against a higher Target.
// *****************************************************************************

`ifndef SMC_I3C_IBI_TARGET_TX_DUT_WIN_TEST_SV
`define SMC_I3C_IBI_TARGET_TX_DUT_WIN_TEST_SV

class smc_i3c_ibi_target_tx_dut_win_test extends
    smc_i3c_ibi_target_tx_dut_loss_test;
  `uvm_component_utils(smc_i3c_ibi_target_tx_dut_win_test)

  function new(string name = "smc_i3c_ibi_target_tx_dut_win_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  protected function bit [6:0] select_higher_target_addr(bit [6:0] dut_addr);
    bit [6:0] candidate;

    for (int unsigned raw = int'(dut_addr) + 1; raw <= 7'h77; raw++) begin
      candidate = raw[6:0];
      if (!is_reserved_dynamic_addr(candidate))
        return candidate;
    end
    `uvm_fatal("IBI_DUT_WIN_ADDR",
               $sformatf("No legal competing Target address exists above DUT address 0x%02h",
                         dut_addr))
    return dut_addr;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg.ibi_source_instance_by_addr.delete(cfg.ibi_secondary_target_addr);
    cfg.ibi_secondary_target_addr = select_higher_target_addr(
      cfg.ibi_target_addr);
    cfg.ibi_source_instance_by_addr[cfg.ibi_secondary_target_addr] = 3'd1;
    cfg.ibi_dut_wins_arbitration = 1'b1;
  endfunction
endclass : smc_i3c_ibi_target_tx_dut_win_test

`endif
