// *****************************************************************************
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 VNCHIP LABS
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// File        : i3c_ibi_controller_rx_overflow_test.sv
// Description : DUT Controller-RX HCI IBI FIFO overflow test.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-09
//
// *****************************************************************************

`ifndef I3C_IBI_CONTROLLER_RX_OVERFLOW_TEST_SV
`define I3C_IBI_CONTROLLER_RX_OVERFLOW_TEST_SV

class i3c_ibi_controller_rx_overflow_test extends i3c_ibi_base_test;
  `uvm_component_utils(i3c_ibi_controller_rx_overflow_test)

  function new(string name = "i3c_ibi_controller_rx_overflow_test",
               uvm_component parent = null);
    super.new(name, parent);
    dut_role = I3C_IBI_DUT_CONTROLLER;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg.ibi_dut_role != I3C_IBI_DUT_CONTROLLER)
      `uvm_fatal("IBI_ROLE",
                 "i3c_ibi_controller_rx_overflow_test requires DUT Controller-RX role")

    cfg.has_ibi_scoreboard = 1'b0;
    cfg.require_ibi_controller_record_irq = 1'b0;
    cfg.ibi_bcr = 8'h06;
    cfg.ibi_bcr_valid = 1'b1;
  endfunction

  virtual function i3c_base_vseq create_vseq();
    return i3c_ibi_controller_rx_fifo_irq_vseq::type_id::create("vseq");
  endfunction
endclass : i3c_ibi_controller_rx_overflow_test

`endif // I3C_IBI_CONTROLLER_RX_OVERFLOW_TEST_SV
