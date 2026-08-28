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
// File        : smc_i3c_ibi_target_tx_invalid_target_vseq.sv
// Description : Target-TX eligibility-negative IBI virtual sequence.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-06
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_TARGET_TX_INVALID_TARGET_VSEQ_SV
`define SMC_I3C_IBI_TARGET_TX_INVALID_TARGET_VSEQ_SV

class smc_i3c_ibi_target_tx_invalid_target_vseq extends smc_i3c_ibi_base_vseq;
  `uvm_object_utils(smc_i3c_ibi_target_tx_invalid_target_vseq)

  // Directly programming inconsistent identity/capability fields is outside
  // this test's runtime eligibility contract. The pinned core accepts any
  // software-written valid Dynamic Address, and BCR is locked once Target mode
  // is enabled; docs/user-guide/ARCHITECTURE.md records that boundary.
  localparam int unsigned QUIET_MARGIN_CYCLES = 64;

  function new(string name = "smc_i3c_ibi_target_tx_invalid_target_vseq");
    super.new(name);
  endfunction

`ifdef SMC_USE_I3C_RTL
`ifdef SMC_USE_I3C_RAL
  protected task reset_ibi_queue(input smc_i3c_ral_model ral,
                                 input string operation);
    uvm_reg_data_t reset_value;

    write_field(ral.I3C_EC.TTI.CONTROL.IBI_EN, 0,
                {operation, ": disable IBI before queue reset"});
    write_action_field(ral.I3C_EC.TTI.RESET_CONTROL.IBI_QUEUE_RST, 1,
                       {operation, ": reset IBI queue"});
    for (int unsigned cycle = 0;
         cycle < vseq_ctx.cfg.ibi_timeout_cycles; cycle++) begin
      read_field(ral.I3C_EC.TTI.RESET_CONTROL.IBI_QUEUE_RST, reset_value,
                 {operation, ": wait for queue reset self-clear"});
      if (reset_value == 0)
        break;
      if (cycle == (vseq_ctx.cfg.ibi_timeout_cycles - 1))
        `uvm_fatal("IBI_INVALID_RESET",
                   $sformatf("%s: IBI queue reset did not self-clear",
                             operation))
      @(posedge vseq_ctx.cfg.vif.clk);
    end
    wait_field_value(ral.I3C_EC.TTI.IBI_QUEUE_DEPTH.IBI_QUEUE_DEPTH, 0,
                     {operation, ": wait for empty IBI queue"});
    clear_w1c_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 1,
                    {operation, ": clear stale IBI_DONE"});
  endtask

  protected task prove_no_bus_ibi(input smc_i3c_ral_model ral,
                                  input uvm_reg_data_t descriptor,
                                  input string operation,
                                  output bit violation_seen);
    uvm_reg_data_t t_aval;
    int unsigned quiet_cycles;
    uvm_event drive_armed;
    uvm_event start_armed;
    uvm_event unknown_armed;
    uvm_event quiet_done;
    bit illegal_start;
    bit illegal_drive;
    bit illegal_unknown;

    read_field(ral.I3C_EC.SoCMgmtIf.T_AVAL_REG.T_AVAL, t_aval,
               {operation, ": read Target Bus Available interval"});
    if ((vseq_ctx.cfg.ibi_timeout_cycles <= QUIET_MARGIN_CYCLES) ||
        (t_aval >= (vseq_ctx.cfg.ibi_timeout_cycles -
                    QUIET_MARGIN_CYCLES)))
      `uvm_fatal("IBI_INVALID_QUIET_CFG",
                 $sformatf("%s: T_AVAL=%0d leaves no complete negative observation window inside timeout=%0d",
                           operation, t_aval,
                           vseq_ctx.cfg.ibi_timeout_cycles))
    quiet_cycles = int'(t_aval) + QUIET_MARGIN_CYCLES;
    illegal_start = 1'b0;
    illegal_drive = 1'b0;
    illegal_unknown = 1'b0;
    violation_seen = 1'b0;
    drive_armed = new({operation, "_drive_armed"});
    start_armed = new({operation, "_start_armed"});
    unknown_armed = new({operation, "_unknown_armed"});
    quiet_done = new({operation, "_quiet_done"});

    fork : invalid_target_quiet_window
      begin
        drive_armed.trigger();
        repeat (quiet_cycles) begin
          @(posedge vseq_ctx.cfg.vif.clk);
          if (vseq_ctx.cfg.vif.i3c_sda_oe === 1'b1)
            illegal_drive = 1'b1;
        end
        quiet_done.trigger();
      end
      begin
        start_armed.trigger();
        forever begin
          @(negedge vseq_ctx.cfg.i3c_vif.sda_i);
          if (vseq_ctx.cfg.i3c_vif.scl_i === 1'b1)
            illegal_start = 1'b1;
        end
      end
      begin
        unknown_armed.trigger();
        forever begin
          @(vseq_ctx.cfg.i3c_vif.scl_i or
            vseq_ctx.cfg.i3c_vif.sda_i);
          if ($isunknown({vseq_ctx.cfg.i3c_vif.scl_i,
                          vseq_ctx.cfg.i3c_vif.sda_i}))
            illegal_unknown = 1'b1;
        end
      end
    join_none

    // All physical observers must be live before the software request reaches
    // the DUT. The previous write-then-observe order could miss the first SDA
    // falling edge and report START=0 even though the waveform contained one.
    drive_armed.wait_on();
    start_armed.wait_on();
    unknown_armed.wait_on();
    write_register(ral.I3C_EC.TTI.IBI_PORT, descriptor,
                   {operation, ": queue software request"});
    quiet_done.wait_on();
    disable invalid_target_quiet_window;

    violation_seen = illegal_drive || illegal_start || illegal_unknown;
    if (violation_seen)
      `uvm_error("IBI_INVALID_ATTEMPT",
                 $sformatf("%s violated the negative bus window: target_sda_oe=%0b START=%0b X/Z=%0b",
                           operation, illegal_drive, illegal_start,
                           illegal_unknown))
    expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 0,
                 {operation, ": no false IBI completion"});
  endtask

  protected task queue_ineligible_request(input smc_i3c_ral_model ral,
                                           input string operation,
                                           input bit enable_ibi,
                                           output bit violation_seen);
    uvm_reg_data_t descriptor;

    descriptor = uvm_reg_data_t'(vseq_ctx.cfg.ibi_basic_mdb) << 24;
    write_field(ral.I3C_EC.TTI.CONTROL.IBI_EN, enable_ibi,
                enable_ibi ? {operation, ": enable IBI engine"} :
                             {operation, ": keep IBI engine disabled"});
    expect_field(ral.I3C_EC.TTI.CONTROL.IBI_EN, enable_ibi,
                 {operation, ": confirm requested IBI enable state"});
    prove_no_bus_ibi(ral, descriptor, operation, violation_seen);

    // "No queue entry" in this negative scenario means no external
    // Controller/HCI IBI record. The software request may remain pending in
    // the local TTI queue; it must not be consumed as a legal bus transfer.
    reset_ibi_queue(ral, operation);
    wait_bus_idle({operation, ": bus remains idle after request cleanup"});
  endtask
`endif
`endif

  virtual task body();
    super.body();
    if (!vseq_ctx.cfg.has_rtl)
      `uvm_fatal("IBI_INVALID_MODE",
                 "smc_i3c_ibi_target_tx_invalid_target_test requires DUT_MODE=rtl")
    if (vseq_ctx.cfg.ibi_dut_role != SMC_I3C_IBI_DUT_TARGET)
      `uvm_fatal("IBI_INVALID_ROLE",
                 "smc_i3c_ibi_target_tx_invalid_target_test requires DUT-target/UVM-controller role")

`ifdef SMC_USE_I3C_RTL
`ifdef SMC_USE_I3C_RAL
    begin
      smc_i3c_ral_model ral;
      int unsigned violation_count;
      bit subcase_violation;

      if (vseq_ctx.i3c_sqr == null)
        `uvm_fatal("IBI_INVALID_SQR",
                   "I3C UVM Controller sequencer is not available")
      ral = get_i3c_ral_model();
      violation_count = 0;
      initialize_target_ibi(ral);

      reset_ibi_queue(ral, "no-address case setup");
      write_field(
        ral.I3C_EC.StdbyCtrlMode.STBY_CR_DEVICE_ADDR.DYNAMIC_ADDR_VALID,
        0, "invalidate target dynamic address");
      queue_ineligible_request(ral, "target without a valid dynamic address",
                               1'b1, subcase_violation);
      violation_count += subcase_violation;

      write_field(ral.I3C_EC.StdbyCtrlMode.STBY_CR_DEVICE_ADDR.DYNAMIC_ADDR,
                  vseq_ctx.cfg.ibi_target_addr,
                  "restore valid target dynamic address");
      write_field(
        ral.I3C_EC.StdbyCtrlMode.STBY_CR_DEVICE_ADDR.DYNAMIC_ADDR_VALID,
        1, "validate restored target dynamic address");
      queue_ineligible_request(ral, "target with runtime IBI_EN clear",
                               1'b0, subcase_violation);
      violation_count += subcase_violation;

      write_field(ral.I3C_EC.TTI.CONTROL.IBI_EN, 0,
                  "leave target IBI engine disabled after negative cases");
      if (violation_count != 0)
        `uvm_fatal("IBI_INVALID_SUBCASES",
                   $sformatf("%0d of 2 runtime eligibility-negative subcases produced prohibited bus activity; see IBI_INVALID_ATTEMPT errors",
                             violation_count))
      `uvm_info("IBI_INVALID_TARGET",
                "PASS: requests without a valid Target address or with IBI_EN clear produced no bus IBI or Controller-visible record",
                UVM_LOW)
    end
`else
    `uvm_fatal("IBI_INVALID_RAL_BUILD",
               "smc_i3c_ibi_target_tx_invalid_target_test requires SMC_USE_I3C_RAL")
`endif
`else
    `uvm_fatal("IBI_INVALID_RTL_BUILD",
               "smc_i3c_ibi_target_tx_invalid_target_test requires SMC_USE_I3C_RTL")
`endif
  endtask
endclass : smc_i3c_ibi_target_tx_invalid_target_vseq

`endif // SMC_I3C_IBI_TARGET_TX_INVALID_TARGET_VSEQ_SV
