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
// File        : smc_i3c_ibi_controller_rx_soft_rst_selfclear_vseq.sv
// Description : Defect reproduction for an inert HCI RESET_CONTROL.SOFT_RST.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-03
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_CONTROLLER_RX_SOFT_RST_SELFCLEAR_VSEQ_SV
`define SMC_I3C_IBI_CONTROLLER_RX_SOFT_RST_SELFCLEAR_VSEQ_SV

// Reproduction of the inert HCI soft reset. No IBI, no bus traffic, CSR only.
//
// Runtime scope is limited to the behavior the generated register contract can
// prove: after software writes the trigger, hardware must write it back to zero.
// RTL inspection also finds no consumer of
// hwif_base_i.RESET_CONTROL.SOFT_RST.value, but the local RDL only says "Reset
// controller from software" and does not specify which configuration CSR must
// return to reset value. That static finding therefore remains in the defect
// report instead of being inferred from an arbitrary CSR marker here.
//
// Verdict semantics, deliberately inverted from a functional test:
//   FAIL (IBI_SOFT_RST_INERT) = the self-clear defect is still present.
//   PASS                      = self-clear is fixed; downstream reset behavior
//                               still needs a separate functional test.
class smc_i3c_ibi_controller_rx_soft_rst_selfclear_vseq extends smc_i3c_ibi_base_vseq;
  `uvm_object_utils(smc_i3c_ibi_controller_rx_soft_rst_selfclear_vseq)

  // Cycles allowed for a self-clear to appear. A real self-clear is one or two
  // cycles after the register write is answered; 16 is slack, not a guess about
  // some slower mechanism.
  localparam int unsigned SOFT_RST_SETTLE_CYCLES = 16;

  function new(string name = "smc_i3c_ibi_controller_rx_soft_rst_selfclear_vseq");
    super.new(name);
  endfunction

  protected virtual function string scenario_name();
    return "Controller HCI SOFT_RST inertness";
  endfunction

  virtual task body();
    super.body();
    if (!vseq_ctx.cfg.has_rtl)
      `uvm_fatal("IBI_SOFT_RST_MODE",
                 "SOFT_RST inertness test requires DUT_MODE=rtl")
    if (vseq_ctx.cfg.ibi_dut_role != SMC_I3C_IBI_DUT_CONTROLLER)
      `uvm_fatal("IBI_SOFT_RST_ROLE",
                 "SOFT_RST inertness vseq requires DUT-controller role")

`ifdef SMC_USE_I3C_RTL
`ifdef SMC_USE_I3C_RAL
    begin
      smc_i3c_ral_model ral;
      uvm_reg_data_t soft_rst_initial;
      uvm_reg_data_t soft_rst_after;
      bit no_self_clear;

      ral = get_i3c_ral_model();

      read_field(ral.I3CBase.RESET_CONTROL.SOFT_RST, soft_rst_initial,
                 "read HCI SOFT_RST before the write");
      if (soft_rst_initial != 0)
        `uvm_fatal("IBI_SOFT_RST_PRECONDITION",
                   $sformatf("HCI RESET_CONTROL.SOFT_RST is already %0d before any write",
                             soft_rst_initial))

      // RESET_CONTROL packs six independent triggers into one register, so only
      // the field's own byte lane may be written; write_field() could dispatch
      // to a parent read-modify-write and replay a neighbouring trigger.
      write_action_field(ral.I3CBase.RESET_CONTROL.SOFT_RST, 1,
                         "assert HCI SOFT_RST");
      repeat (SOFT_RST_SETTLE_CYCLES) @(posedge vseq_ctx.cfg.vif.clk);

      read_field(ral.I3CBase.RESET_CONTROL.SOFT_RST, soft_rst_after,
                 "read HCI SOFT_RST after the write");
      no_self_clear = (soft_rst_after != 0);

      if (no_self_clear)
        `uvm_error("IBI_SOFT_RST_INERT",
                   $sformatf("HCI RESET_CONTROL.SOFT_RST read back as %0d after %0d cycles instead of self-clearing. RTL inspection shows plain CSR storage (I3CCSR.sv:3864-3890), a hardware-write struct tied off at hci.sv:442 and no consumer in src/.",
                             soft_rst_after, SOFT_RST_SETTLE_CYCLES))
      else
        `uvm_info("IBI_SOFT_RST_INERT",
                  "HCI RESET_CONTROL.SOFT_RST self-cleared. Re-check the static no-consumer finding and add a contract-backed functional reset test before declaring SOFT_RST complete.",
                  UVM_LOW)

      `uvm_info("IBI_SOFT_RST",
                $sformatf("%s: soft_rst_after=%0d settle_cycles=%0d",
                          scenario_name(), soft_rst_after,
                          SOFT_RST_SETTLE_CYCLES),
                UVM_LOW)
    end
`else
    `uvm_fatal("IBI_SOFT_RST_RAL_BUILD",
               "SOFT_RST inertness test requires SMC_USE_I3C_RAL")
`endif
`else
    `uvm_fatal("IBI_SOFT_RST_RTL_BUILD",
               "SOFT_RST inertness test requires SMC_USE_I3C_RTL")
`endif
  endtask
endclass : smc_i3c_ibi_controller_rx_soft_rst_selfclear_vseq

`endif // SMC_I3C_IBI_CONTROLLER_RX_SOFT_RST_SELFCLEAR_VSEQ_SV
