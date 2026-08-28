// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 VNCHIP LABS
// Authors: Huynh Pham Anh Duy, Thai Hai Dang
// File: smc_i3c_ibi_controller_rx_multi_target_queue_pressure_test.sv
// Description: DUT-Controller arbitration and IBI queue pressure test.
`ifndef SMC_I3C_IBI_CONTROLLER_RX_MULTI_TARGET_QUEUE_PRESSURE_TEST_SV
`define SMC_I3C_IBI_CONTROLLER_RX_MULTI_TARGET_QUEUE_PRESSURE_TEST_SV

class smc_i3c_ibi_controller_rx_multi_target_queue_pressure_test extends smc_i3c_ibi_controller_rx_multi_target_test;
  `uvm_component_utils(smc_i3c_ibi_controller_rx_multi_target_queue_pressure_test)
  function new(string name = "smc_i3c_ibi_controller_rx_multi_target_queue_pressure_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  virtual function smc_peripherals_base_vseq create_vseq();
    return smc_i3c_ibi_controller_rx_multi_target_queue_pressure_vseq::type_id::create("vseq");
  endfunction
endclass

`endif
