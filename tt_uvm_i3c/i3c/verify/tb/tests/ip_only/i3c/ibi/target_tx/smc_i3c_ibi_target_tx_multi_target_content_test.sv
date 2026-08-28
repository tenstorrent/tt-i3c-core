// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 VNCHIP LABS
// Authors: Huynh Pham Anh Duy, Thai Hai Dang
// File: smc_i3c_ibi_target_tx_multi_target_content_test.sv
// Description: DUT-Target arbitration followed by MDB/payload checks.
`ifndef SMC_I3C_IBI_TARGET_TX_MULTI_TARGET_CONTENT_TEST_SV
`define SMC_I3C_IBI_TARGET_TX_MULTI_TARGET_CONTENT_TEST_SV

class smc_i3c_ibi_target_tx_multi_target_content_test extends smc_i3c_ibi_target_tx_multi_target_test;
  `uvm_component_utils(smc_i3c_ibi_target_tx_multi_target_content_test)
  function new(string name = "smc_i3c_ibi_target_tx_multi_target_content_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  virtual function smc_peripherals_base_vseq create_vseq();
    return smc_i3c_ibi_target_tx_multi_target_content_vseq::type_id::create("vseq");
  endfunction
endclass

`endif
