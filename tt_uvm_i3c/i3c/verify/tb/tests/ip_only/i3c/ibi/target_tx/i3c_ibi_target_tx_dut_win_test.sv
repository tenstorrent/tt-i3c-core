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
// File        : i3c_ibi_target_tx_dut_win_test.sv
// Description : DUT-Target wins real IBI arbitration against a higher Target.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-09-08
//
// *****************************************************************************

`ifndef I3C_IBI_TARGET_TX_DUT_WIN_TEST_SV
`define I3C_IBI_TARGET_TX_DUT_WIN_TEST_SV

class i3c_ibi_target_tx_dut_win_test extends
    i3c_ibi_target_tx_dut_loss_test;
  `uvm_component_utils(i3c_ibi_target_tx_dut_win_test)

  function new(string name = "i3c_ibi_target_tx_dut_win_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  protected function bit [6:0] select_higher_target_addr(bit [6:0] dut_addr);
    bit [6:0] candidate;

    for (int unsigned raw = int'(dut_addr) + 1; raw <= 7'h77; raw++) begin
      candidate = raw[6:0];
      if (!is_reserved_dynamic_addr(candidate))
        return candidate;
    end
    `uvm_fatal("IBI_DUT_WIN_ADDR",
               $sformatf("No legal competing Target address exists above DUT address 0x%02h",
                         dut_addr))
    return dut_addr;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg.ibi_source_instance_by_addr.delete(cfg.ibi_secondary_target_addr);
    cfg.ibi_secondary_target_addr = select_higher_target_addr(
      cfg.ibi_target_addr);
    cfg.ibi_source_instance_by_addr[cfg.ibi_secondary_target_addr] = 3'd1;
    cfg.ibi_dut_wins_arbitration = 1'b1;
  endfunction
endclass : i3c_ibi_target_tx_dut_win_test

`endif
