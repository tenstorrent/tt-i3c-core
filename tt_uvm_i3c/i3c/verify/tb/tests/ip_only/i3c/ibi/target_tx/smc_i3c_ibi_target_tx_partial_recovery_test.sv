// *****************************************************************************
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 VNCHIP LABS
//
// File        : smc_i3c_ibi_target_tx_partial_recovery_test.sv
// Description : Target IBI partial-data protocol-error and recovery test.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-18
// ****************************************************************************

`ifndef SMC_I3C_IBI_TARGET_TX_PARTIAL_RECOVERY_TEST_SV
`define SMC_I3C_IBI_TARGET_TX_PARTIAL_RECOVERY_TEST_SV

class smc_i3c_ibi_target_tx_partial_recovery_test extends
    smc_i3c_ibi_target_tx_mdb_payload_test;
  `uvm_component_utils(smc_i3c_ibi_target_tx_partial_recovery_test)

  function new(string name = "smc_i3c_ibi_target_tx_partial_recovery_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg.ibi_expect_partial_data = 1'b1;
    // The Host returns its two-byte request including the abort boundary; the
    // passive monitor publishes the one fully completed MDB byte before it.
    cfg.ibi_partial_host_rx_bytes = 2;
    cfg.ibi_partial_passive_bytes = 1;
    cfg.has_ibi_recovery_checker = 1'b1;
  endfunction
endclass : smc_i3c_ibi_target_tx_partial_recovery_test

`endif // SMC_I3C_IBI_TARGET_TX_PARTIAL_RECOVERY_TEST_SV
