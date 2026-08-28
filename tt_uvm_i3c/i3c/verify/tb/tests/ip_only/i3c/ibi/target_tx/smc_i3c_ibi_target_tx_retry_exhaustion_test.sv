// *****************************************************************************
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 VNCHIP LABS
//
// File        : smc_i3c_ibi_target_tx_retry_exhaustion_test.sv
// Description : Finite Target IBI retry-limit exhaustion test.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-18
// ****************************************************************************

`ifndef SMC_I3C_IBI_TARGET_TX_RETRY_EXHAUSTION_TEST_SV
`define SMC_I3C_IBI_TARGET_TX_RETRY_EXHAUSTION_TEST_SV

class smc_i3c_ibi_target_tx_retry_exhaustion_test extends
    smc_i3c_ibi_target_tx_retry_arbitration_test;
  `uvm_component_utils(smc_i3c_ibi_target_tx_retry_exhaustion_test)

  function new(string name = "smc_i3c_ibi_target_tx_retry_exhaustion_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg.ibi_retry_exhaustion = 1'b1;
  endfunction
endclass : smc_i3c_ibi_target_tx_retry_exhaustion_test

`endif // SMC_I3C_IBI_TARGET_TX_RETRY_EXHAUSTION_TEST_SV
