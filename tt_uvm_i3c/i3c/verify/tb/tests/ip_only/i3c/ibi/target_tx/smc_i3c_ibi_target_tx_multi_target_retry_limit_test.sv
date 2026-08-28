// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 VNCHIP LABS
// Authors: Huynh Pham Anh Duy, Thai Hai Dang
// File: smc_i3c_ibi_target_tx_multi_target_retry_limit_test.sv
// Description: Focused DUT-Target bounded retry-limit test.
`ifndef SMC_I3C_IBI_TARGET_TX_MULTI_TARGET_RETRY_LIMIT_TEST_SV
`define SMC_I3C_IBI_TARGET_TX_MULTI_TARGET_RETRY_LIMIT_TEST_SV

class smc_i3c_ibi_target_tx_multi_target_retry_limit_test extends
    smc_i3c_ibi_target_tx_retry_arbitration_test;
  `uvm_component_utils(smc_i3c_ibi_target_tx_multi_target_retry_limit_test)
  function new(string name = "smc_i3c_ibi_target_tx_multi_target_retry_limit_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  virtual function smc_peripherals_base_vseq create_vseq();
    return smc_i3c_ibi_target_tx_multi_target_retry_limit_vseq::type_id::create("vseq");
  endfunction
endclass

`endif
