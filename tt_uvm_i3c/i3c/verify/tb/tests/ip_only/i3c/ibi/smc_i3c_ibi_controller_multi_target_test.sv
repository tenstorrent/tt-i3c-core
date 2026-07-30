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
// File        : smc_i3c_ibi_controller_multi_target_test.sv
// Description : UVM test for multi-target IBI arbitration by the Controller.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-25
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_CONTROLLER_MULTI_TARGET_TEST_SV
`define SMC_I3C_IBI_CONTROLLER_MULTI_TARGET_TEST_SV

class smc_i3c_ibi_controller_multi_target_test extends
    smc_i3c_ibi_controller_receive_test;
  `uvm_component_utils(smc_i3c_ibi_controller_multi_target_test)

  function new(string name = "smc_i3c_ibi_controller_multi_target_test",
               uvm_component parent = null);
    super.new(name, parent);
    controller_target_count = 2;
  endfunction

  protected function bit [6:0] select_secondary_addr(bit [6:0] primary);
    bit [6:0] candidate;

    for (int unsigned raw = int'(primary) + 1; raw < 7'h78; raw++) begin
      candidate = raw[6:0];
      if (!is_reserved_dynamic_addr(candidate))
        return candidate;
    end
    for (int unsigned raw = 8; raw < int'(primary); raw++) begin
      candidate = raw[6:0];
      if (!is_reserved_dynamic_addr(candidate))
        return candidate;
    end
    `uvm_fatal("IBI_CTRL_MULTI_ADDR",
               "Unable to select a second legal dynamic address")
    return primary;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    int unsigned secondary_addr_plusarg;

    super.build_phase(phase);
    cfg.ibi_secondary_target_addr =
      select_secondary_addr(cfg.ibi_target_addr);
    if ($value$plusargs("IBI_SECONDARY_TARGET_ADDR=%h",
                        secondary_addr_plusarg)) begin
      if ((secondary_addr_plusarg > 7'h7f) ||
          is_reserved_dynamic_addr(secondary_addr_plusarg[6:0]) ||
          (secondary_addr_plusarg[6:0] == cfg.ibi_target_addr))
        `uvm_fatal("IBI_SECONDARY_TARGET_ADDR",
                   $sformatf("Invalid secondary Target address 0x%0h",
                             secondary_addr_plusarg))
      cfg.ibi_secondary_target_addr = secondary_addr_plusarg[6:0];
    end
    cfg.ibi_source_instance_by_addr[cfg.ibi_secondary_target_addr] = 3'd1;
    cfg.ibi_requester_count = 2;
    cfg.vif.i3c_controller_expected_addr = cfg.ibi_target_addr;
  endfunction

  virtual function smc_peripherals_base_vseq create_vseq();
    return smc_i3c_ibi_controller_multi_target_vseq::type_id::create(
      "vseq");
  endfunction
endclass : smc_i3c_ibi_controller_multi_target_test

`endif // SMC_I3C_IBI_CONTROLLER_MULTI_TARGET_TEST_SV
