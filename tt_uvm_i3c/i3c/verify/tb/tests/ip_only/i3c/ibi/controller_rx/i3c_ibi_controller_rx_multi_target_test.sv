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
// File        : i3c_ibi_controller_rx_multi_target_test.sv
// Description : UVM test for multi-target IBI arbitration by the Controller.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-25
//
// *****************************************************************************

`ifndef I3C_IBI_CONTROLLER_RX_MULTI_TARGET_TEST_SV
`define I3C_IBI_CONTROLLER_RX_MULTI_TARGET_TEST_SV

class i3c_ibi_controller_rx_multi_target_test extends
    i3c_ibi_controller_rx_basic_test;
  `uvm_component_utils(i3c_ibi_controller_rx_multi_target_test)

  function new(string name = "i3c_ibi_controller_rx_multi_target_test",
               uvm_component parent = null);
    super.new(name, parent);
    controller_target_count = 4;
  endfunction

  protected function bit [6:0] select_quaternary_addr(
      bit [6:0] primary,
      bit [6:0] secondary,
      bit [6:0] tertiary);
    bit [6:0] candidate;

    for (int unsigned raw = int'(tertiary) + 1; raw < 7'h78; raw++) begin
      candidate = raw[6:0];
      if (!is_reserved_dynamic_addr(candidate) &&
          (candidate != primary) && (candidate != secondary))
        return candidate;
    end
    for (int unsigned raw = 8; raw < 7'h78; raw++) begin
      candidate = raw[6:0];
      if (!is_reserved_dynamic_addr(candidate) &&
          (candidate != primary) && (candidate != secondary) &&
          (candidate != tertiary))
        return candidate;
    end
    `uvm_fatal("IBI_CTRL_MULTI_ADDR",
               "Unable to select a fourth legal dynamic address")
    return primary;
  endfunction

  protected function bit [6:0] select_tertiary_addr(
      bit [6:0] primary,
      bit [6:0] secondary);
    bit [6:0] candidate;

    for (int unsigned raw = int'(secondary) + 1; raw < 7'h78; raw++) begin
      candidate = raw[6:0];
      if (!is_reserved_dynamic_addr(candidate) && (candidate != primary))
        return candidate;
    end
    for (int unsigned raw = 8; raw < 7'h78; raw++) begin
      candidate = raw[6:0];
      if (!is_reserved_dynamic_addr(candidate) &&
          (candidate != primary) && (candidate != secondary))
        return candidate;
    end
    `uvm_fatal("IBI_CTRL_MULTI_ADDR",
               "Unable to select a third legal dynamic address")
    return primary;
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
    int unsigned tertiary_addr_plusarg;
    int unsigned quaternary_addr_plusarg;

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
    cfg.ibi_target_addr_by_slot[2] = select_tertiary_addr(
      cfg.ibi_target_addr, cfg.ibi_secondary_target_addr);
    if ($value$plusargs("IBI_TERTIARY_TARGET_ADDR=%h",
                        tertiary_addr_plusarg)) begin
      if ((tertiary_addr_plusarg > 7'h7f) ||
          is_reserved_dynamic_addr(tertiary_addr_plusarg[6:0]) ||
          (tertiary_addr_plusarg[6:0] == cfg.ibi_target_addr) ||
          (tertiary_addr_plusarg[6:0] == cfg.ibi_secondary_target_addr))
        `uvm_fatal("IBI_TERTIARY_TARGET_ADDR",
                   $sformatf("Invalid tertiary Target address 0x%0h",
                             tertiary_addr_plusarg))
      cfg.ibi_target_addr_by_slot[2] = tertiary_addr_plusarg[6:0];
    end
    cfg.ibi_target_addr_by_slot[3] = select_quaternary_addr(
      cfg.ibi_target_addr, cfg.ibi_secondary_target_addr,
      cfg.ibi_target_addr_by_slot[2]);
    if ($value$plusargs("IBI_QUATERNARY_TARGET_ADDR=%h",
                        quaternary_addr_plusarg)) begin
      if ((quaternary_addr_plusarg > 7'h7f) ||
          is_reserved_dynamic_addr(quaternary_addr_plusarg[6:0]) ||
          (quaternary_addr_plusarg[6:0] == cfg.ibi_target_addr) ||
          (quaternary_addr_plusarg[6:0] == cfg.ibi_secondary_target_addr) ||
          (quaternary_addr_plusarg[6:0] == cfg.ibi_target_addr_by_slot[2]))
        `uvm_fatal("IBI_QUATERNARY_TARGET_ADDR",
                   $sformatf("Invalid quaternary Target address 0x%0h",
                             quaternary_addr_plusarg))
      cfg.ibi_target_addr_by_slot[3] = quaternary_addr_plusarg[6:0];
    end
    cfg.ibi_source_instance_by_addr[cfg.ibi_secondary_target_addr] = 3'd1;
    cfg.ibi_source_instance_by_addr[cfg.ibi_target_addr_by_slot[2]] = 3'd2;
    cfg.ibi_source_instance_by_addr[cfg.ibi_target_addr_by_slot[3]] = 3'd3;
    cfg.ibi_requester_count = 4;
    cfg.vif.i3c_controller_expected_addr = cfg.ibi_target_addr;
  endfunction

  virtual function i3c_base_vseq create_vseq();
    return i3c_ibi_controller_rx_multi_target_vseq::type_id::create(
      "vseq");
  endfunction
endclass : i3c_ibi_controller_rx_multi_target_test

`endif // I3C_IBI_CONTROLLER_RX_MULTI_TARGET_TEST_SV
