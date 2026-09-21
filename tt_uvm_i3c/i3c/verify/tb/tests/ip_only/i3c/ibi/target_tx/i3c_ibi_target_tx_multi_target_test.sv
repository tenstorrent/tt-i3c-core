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
// File        : i3c_ibi_target_tx_multi_target_test.sv
// Description : DUT-Target test for concurrent multi-Target IBI arbitration.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-04
//
// *****************************************************************************

`ifndef I3C_IBI_TARGET_TX_MULTI_TARGET_TEST_SV
`define I3C_IBI_TARGET_TX_MULTI_TARGET_TEST_SV

class i3c_ibi_target_tx_multi_target_test extends i3c_ibi_base_test;
  `uvm_component_utils(i3c_ibi_target_tx_multi_target_test)

  function new(string name = "i3c_ibi_target_tx_multi_target_test",
               uvm_component parent = null);
    super.new(name, parent);
    // The primary agent is the UVM Host for the DUT Target.  A second Device
    // agent supplies the competing Target address on the same physical bus.
    controller_target_count = 3;
  endfunction

  protected function bit [6:0] select_higher_secondary_addr(
      bit [6:0] dut_addr);
    bit [6:0] candidate;

    for (int unsigned raw = int'(dut_addr) + 1; raw < 7'h78; raw++) begin
      candidate = raw[6:0];
      if (!is_reserved_dynamic_addr(candidate))
        return candidate;
    end
    `uvm_fatal("IBI_MULTI_ADDR",
               $sformatf("No legal competing Target address exists above DUT address 0x%02h",
                         dut_addr))
    return dut_addr;
  endfunction

  protected function bit [6:0] select_tertiary_addr(
      bit [6:0] dut_addr,
      bit [6:0] secondary_addr);
    bit [6:0] candidate;

    for (int unsigned raw = int'(secondary_addr) + 1;
         raw < 7'h78; raw++) begin
      candidate = raw[6:0];
      if (!is_reserved_dynamic_addr(candidate) && (candidate != dut_addr))
        return candidate;
    end
    `uvm_fatal("IBI_MULTI_ADDR",
               $sformatf("No second legal competing Target address exists above 0x%02h",
                         secondary_addr))
    return dut_addr;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    int unsigned secondary_addr_plusarg;
    int unsigned tertiary_addr_plusarg;

    super.build_phase(phase);
    if (cfg.ibi_dut_role != I3C_IBI_DUT_TARGET)
      `uvm_fatal("IBI_MULTI_ROLE",
                 "i3c_ibi_target_tx_multi_target_test requires DUT-Target role")

    cfg.ibi_secondary_target_addr =
      select_higher_secondary_addr(cfg.ibi_target_addr);
    if ($value$plusargs("IBI_SECONDARY_TARGET_ADDR=%h",
                        secondary_addr_plusarg)) begin
      if ((secondary_addr_plusarg > 7'h77) ||
          is_reserved_dynamic_addr(secondary_addr_plusarg[6:0]) ||
          (secondary_addr_plusarg[6:0] <= cfg.ibi_target_addr))
        `uvm_fatal("IBI_SECONDARY_TARGET_ADDR",
                   $sformatf("Secondary Target address 0x%0h must be legal and greater than DUT address 0x%02h",
                             secondary_addr_plusarg,
                             cfg.ibi_target_addr))
      cfg.ibi_secondary_target_addr = secondary_addr_plusarg[6:0];
    end
    cfg.ibi_target_addr_by_slot[2] = select_tertiary_addr(
      cfg.ibi_target_addr, cfg.ibi_secondary_target_addr);
    if ($value$plusargs("IBI_TERTIARY_TARGET_ADDR=%h",
                        tertiary_addr_plusarg)) begin
      if ((tertiary_addr_plusarg > 7'h77) ||
          is_reserved_dynamic_addr(tertiary_addr_plusarg[6:0]) ||
          (tertiary_addr_plusarg[6:0] <= cfg.ibi_secondary_target_addr))
        `uvm_fatal("IBI_TERTIARY_TARGET_ADDR",
                   $sformatf("Tertiary Target address 0x%0h must be legal and greater than secondary address 0x%02h",
                             tertiary_addr_plusarg,
                             cfg.ibi_secondary_target_addr))
      cfg.ibi_target_addr_by_slot[2] = tertiary_addr_plusarg[6:0];
    end
    cfg.ibi_source_instance_by_addr[cfg.ibi_secondary_target_addr] = 3'd1;
    cfg.ibi_source_instance_by_addr[cfg.ibi_target_addr_by_slot[2]] = 3'd2;
    cfg.ibi_filter_external_target_observations = 1'b1;

  endfunction

  virtual function i3c_base_vseq create_vseq();
    return i3c_ibi_target_tx_multi_target_vseq::type_id::create("vseq");
  endfunction
endclass : i3c_ibi_target_tx_multi_target_test

`endif // I3C_IBI_TARGET_TX_MULTI_TARGET_TEST_SV
