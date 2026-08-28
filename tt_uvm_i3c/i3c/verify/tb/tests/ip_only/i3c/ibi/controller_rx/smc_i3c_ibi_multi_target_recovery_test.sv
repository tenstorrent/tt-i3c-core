// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 VNCHIP LABS
// Authors: Huynh Pham Anh Duy, Thai Hai Dang
// File: smc_i3c_ibi_multi_target_recovery_test.sv
// Description: DUT-Controller multi-requester recovery and forward-progress test.
`ifndef SMC_I3C_IBI_MULTI_TARGET_RECOVERY_TEST_SV
`define SMC_I3C_IBI_MULTI_TARGET_RECOVERY_TEST_SV

class smc_i3c_ibi_multi_target_recovery_test extends smc_i3c_ibi_controller_rx_multi_target_test;
  `uvm_component_utils(smc_i3c_ibi_multi_target_recovery_test)
  function new(string name = "smc_i3c_ibi_multi_target_recovery_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // The composite recovery sequence arms the passive cleanup/forward-
    // progress checker after completing multi-requester arbitration.
    cfg.has_ibi_recovery_checker = 1'b1;
  endfunction
  virtual function smc_peripherals_base_vseq create_vseq();
    return smc_i3c_ibi_multi_target_recovery_vseq::type_id::create("vseq");
  endfunction
endclass

`endif
