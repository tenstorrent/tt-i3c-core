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
// File        : i3c_ibi_base_vseq.sv
// Description : Base virtual sequence for I3C IBI scenarios.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-24
//
// *****************************************************************************

`ifndef I3C_IBI_BASE_VSEQ_SV
`define I3C_IBI_BASE_VSEQ_SV

class i3c_ibi_base_vseq extends i3c_base_vseq;
  `uvm_object_utils(i3c_ibi_base_vseq)

  localparam bit [1:0] STBY_CR_TARGET_MODE = 2'b10;
  localparam int unsigned BCR_IBI_CAPABLE_BIT = I3C_BCR_IBI_CAPABLE_BIT;
  localparam int unsigned BCR_MDB_CAPABLE_BIT = I3C_BCR_MDB_CAPABLE_BIT;

  function new(string name = "i3c_ibi_base_vseq");
    super.new(name);
  endfunction

`ifdef I3C_DV_NATIVE_RTL
  protected function virtual i3c_if i3c_vif_for_slot(
      input int unsigned slot);
    virtual i3c_if slot_vif;

    if (slot >= TB_MAX_IBI_REQUESTERS) begin
      `uvm_fatal("IBI_TARGET_VIF_SLOT",
                 $sformatf("Target slot %0d exceeds the supported range 0..%0d",
                           slot, TB_MAX_IBI_REQUESTERS - 1))
      return null;
    end

    // Slot zero shares the primary DUT-facing interface. Additional Target
    // agents use the dedicated interface array populated by the base test.
    slot_vif = (slot == 0) ? vseq_ctx.cfg.i3c_vif :
                             vseq_ctx.cfg.i3c_target_vif[slot];
    if (slot_vif == null) begin
      `uvm_fatal("IBI_TARGET_VIF_NULL",
                 $sformatf("No I3C virtual interface is configured for Target slot %0d",
                           slot))
      return null;
    end

    return slot_vif;
  endfunction
`endif

`ifdef I3C_DV_NATIVE_RAL
  `include "i3c_ibi_ral_tasks.svh"

`ifdef I3C_DV_NATIVE_RTL
  `include "i3c_ibi_bus_prime_tasks.svh"
`endif
`endif

  protected task wait_irq(bit expected, string operation);
    for (int unsigned cycle = 0;
         cycle < vseq_ctx.cfg.ibi_timeout_cycles; cycle++) begin
      if (vseq_ctx.cfg.vif.i3c_irq === expected)
        return;
      @(posedge vseq_ctx.cfg.vif.clk);
    end
    `uvm_fatal("IBI_IRQ_TIMEOUT",
               $sformatf("%s: i3c_irq did not become %0b", operation, expected))
  endtask

  protected task wait_scoreboard_completion(int unsigned expected_count,
                                             string operation);
    for (int unsigned cycle = 0;
         cycle < vseq_ctx.cfg.ibi_timeout_cycles; cycle++) begin
      if (vseq_ctx.cfg.ibi_sb_completion_count >= expected_count)
        return;
      @(posedge vseq_ctx.cfg.vif.clk);
    end
    `uvm_fatal("IBI_SB_TIMEOUT",
               $sformatf("%s: scoreboard completion count did not reach %0d (actual=%0d)",
                         operation, expected_count,
                         vseq_ctx.cfg.ibi_sb_completion_count))
  endtask

  protected task wait_bus_idle(string operation);
`ifdef I3C_DV_NATIVE_RTL
    for (int unsigned cycle = 0;
         cycle < vseq_ctx.cfg.ibi_timeout_cycles; cycle++) begin
      if ((vseq_ctx.cfg.i3c_vif.scl_i === 1'b1) &&
          (vseq_ctx.cfg.i3c_vif.sda_i === 1'b1))
        return;
      @(posedge vseq_ctx.cfg.vif.clk);
    end
    `uvm_fatal("IBI_BUS_IDLE_TIMEOUT",
               $sformatf("%s: I3C bus did not return idle", operation))
`else
    `uvm_fatal("IBI_BUS_IDLE_BUILD", "I3C bus wait requires native I3C RTL mode")
`endif
  endtask

endclass : i3c_ibi_base_vseq

`endif // I3C_IBI_BASE_VSEQ_SV
