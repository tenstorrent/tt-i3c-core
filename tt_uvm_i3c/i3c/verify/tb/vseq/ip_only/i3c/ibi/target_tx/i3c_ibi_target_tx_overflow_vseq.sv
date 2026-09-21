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
// File        : i3c_ibi_target_tx_overflow_vseq.sv
// Description : Independent Target-TX combined-TTI and Controller-RX HCI overflow cases.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-06
//
// *****************************************************************************

`ifndef I3C_IBI_TARGET_TX_OVERFLOW_VSEQ_SV
`define I3C_IBI_TARGET_TX_OVERFLOW_VSEQ_SV

class i3c_ibi_target_tx_overflow_vseq extends i3c_ibi_base_vseq;
  `uvm_object_utils(i3c_ibi_target_tx_overflow_vseq)

  localparam bit [31:0] OVERFLOW_SENTINEL = 32'hdeadc0de;
  localparam string TARGET_IBI_FIFO_PATH =
    "tb_i3c_top.u_dut.u_i3c_core.i3c.xrecovery_handler.ibi_queue.fifo.gen_normal_fifo";

  function new(string name = "i3c_ibi_target_tx_overflow_vseq");
    super.new(name);
  endfunction

`ifdef I3C_DV_NATIVE_RTL
`ifdef I3C_DV_NATIVE_RAL
  protected task reset_target_ibi_queue(input i3c_ral_model ral);
    uvm_reg_data_t reset_value;

    write_action_field(ral.I3C_EC.TTI.RESET_CONTROL.IBI_QUEUE_RST, 1,
                       "reset Target TTI IBI queue after overflow check");
    for (int unsigned cycle = 0;
         cycle < vseq_ctx.cfg.ibi_timeout_cycles; cycle++) begin
      read_field(ral.I3C_EC.TTI.RESET_CONTROL.IBI_QUEUE_RST, reset_value,
                 "wait for Target TTI IBI queue reset self-clear");
      if (reset_value == 0)
        break;
      if (cycle == (vseq_ctx.cfg.ibi_timeout_cycles - 1))
        `uvm_fatal("IBI_OVERFLOW_RESET",
                   "Target TTI IBI queue reset did not self-clear")
      @(posedge vseq_ctx.cfg.vif.clk);
    end
    wait_field_value(ral.I3C_EC.TTI.IBI_QUEUE_DEPTH.IBI_QUEUE_DEPTH, 0,
                     "wait for empty Target TTI IBI queue after reset");
  endtask

  protected task fill_and_overflow_target_queue(
      input i3c_ral_model ral,
      input bit payload_case,
      input string operation);
    i3c_ibi_recovery_checker recovery_checker;
    uvm_reg_data_t depth_value;
    uvm_reg_data_t fill_word;
    int unsigned payload_bytes;
    int unsigned write_count;
    uvm_hdl_data_t write_pointer_before;
    uvm_hdl_data_t write_pointer_after;
    uvm_hdl_data_t storage_before;
    uvm_hdl_data_t storage_after;
    string write_pointer_path;
    string storage_path;
    bit recovery_completed;
    bit recovery_passed;

    payload_bytes = vseq_ctx.cfg.ibi_queue_size * 4;
    if (payload_case && (payload_bytes > 8'hff))
      `uvm_fatal("IBI_TARGET_OVERFLOW_PAYLOAD",
                 $sformatf("TTI capacity %0d needs %0d payload bytes, above the 8-bit IBI descriptor length",
                           vseq_ctx.cfg.ibi_queue_size, payload_bytes))

    write_count = 0;
    do begin
      read_field(ral.I3C_EC.TTI.IBI_QUEUE_DEPTH.IBI_QUEUE_DEPTH,
                 depth_value, {operation, ": observe queue fill level"});
      if (depth_value == vseq_ctx.cfg.ibi_queue_size)
        break;
      if (depth_value > vseq_ctx.cfg.ibi_queue_size)
        `uvm_fatal("IBI_TARGET_OVERFLOW_DEPTH",
                   $sformatf("TTI IBI depth %0d exceeded capacity %0d",
                             depth_value, vseq_ctx.cfg.ibi_queue_size))
      if (write_count > (vseq_ctx.cfg.ibi_queue_size + 1))
        `uvm_fatal("IBI_TARGET_OVERFLOW_FILL",
                   $sformatf("TTI IBI queue did not reach capacity %0d after %0d writes",
                             vseq_ctx.cfg.ibi_queue_size, write_count))

      // The first word may be prefetched by the Target IBI engine even while
      // IBI_EN is clear. Fill to the architectural depth instead of assuming
      // one AXI write always increments the FIFO level. In the payload case,
      // the descriptor declares exactly one queue-capacity of payload DWORDs;
      // in the descriptor case every word has a zero payload length.
      if (payload_case && (write_count == 0))
        fill_word = (uvm_reg_data_t'(vseq_ctx.cfg.ibi_basic_mdb) << 24) |
                    uvm_reg_data_t'(payload_bytes[7:0]);
      else if (payload_case)
        fill_word = 32'ha500_0000 | write_count[15:0];
      else
        fill_word = (uvm_reg_data_t'(8'h80 + write_count[7:0]) << 24);
      write_register(ral.I3C_EC.TTI.IBI_PORT, fill_word,
                     $sformatf("%s: fill queue word %0d", operation,
                               write_count));
      write_count++;
    end while (1);

    expect_field(ral.I3C_EC.TTI.QUEUE_STATUS.IBI_QUEUE_FULL, 1,
                 {operation, ": confirm queue full"});
    expect_field(ral.I3C_EC.TTI.QUEUE_STATUS.IBI_QUEUE_EMPTY, 0,
                 {operation, ": confirm full queue is not empty"});

    // This is a project-specific TTI FIFO capacity test. Snapshot the actual
    // RTL FIFO state—not the RAL mirror—so unchanged depth alone cannot hide a
    // pointer advance, wrap overwrite, sentinel commit, or ordering change.
    write_pointer_path = {TARGET_IBI_FIFO_PATH, ".fifo_wptr"};
    storage_path = {TARGET_IBI_FIFO_PATH, ".storage"};
    if (!uvm_hdl_read(write_pointer_path, write_pointer_before))
      `uvm_fatal("IBI_TARGET_OVERFLOW_HDL",
                 $sformatf("Cannot read Target IBI FIFO write pointer at %s",
                           write_pointer_path))
    if (!uvm_hdl_read(storage_path, storage_before))
      `uvm_fatal("IBI_TARGET_OVERFLOW_HDL",
                 $sformatf("Cannot read Target IBI FIFO storage at %s",
                           storage_path))

    // TTI writes are acknowledged even when the queue is full. The required
    // overflow behavior is therefore proven by unchanged architectural depth
    // and a continuously asserted FULL indication, not by AXI SLVERR.
    write_register(ral.I3C_EC.TTI.IBI_PORT, OVERFLOW_SENTINEL,
                   {operation, ": attempt one write beyond capacity"});
    repeat (4)
      @(posedge vseq_ctx.cfg.vif.clk);
    if (!uvm_hdl_read(write_pointer_path, write_pointer_after) ||
        !uvm_hdl_read(storage_path, storage_after))
      `uvm_fatal("IBI_TARGET_OVERFLOW_HDL",
                 "Cannot read Target IBI FIFO state after excess write")
    if (write_pointer_after !== write_pointer_before)
      `uvm_fatal("IBI_TARGET_OVERFLOW_POINTER",
                 $sformatf("%s advanced write pointer on excess write: before=0x%0h after=0x%0h",
                           operation, write_pointer_before,
                           write_pointer_after))
    if (storage_after !== storage_before)
      `uvm_fatal("IBI_TARGET_OVERFLOW_CORRUPTION",
                 $sformatf("%s changed retained FIFO storage on excess write",
                           operation))
    expect_field(ral.I3C_EC.TTI.IBI_QUEUE_DEPTH.IBI_QUEUE_DEPTH,
                 vseq_ctx.cfg.ibi_queue_size,
                 {operation, ": confirm excess write was not committed"});
    expect_field(ral.I3C_EC.TTI.QUEUE_STATUS.IBI_QUEUE_FULL, 1,
                 {operation, ": confirm FULL survives overflow"});
    expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 0,
                 {operation, ": confirm no false IBI completion"});

    recovery_checker = vseq_ctx.i3c_ibi_recovery_checker;
    if (recovery_checker == null)
      `uvm_fatal("IBI_TARGET_OVERFLOW_RECOVERY",
                 "Target overflow recovery checker is unavailable")
    // The excess write above is the independently proven overflow trigger.
    // Arm before the architectural queue reset, then require the checker to
    // observe the reset, empty queue, low IRQ and idle bus. No follow-up IBI is
    // required here because this task runs twice; the second phase itself is
    // the subsequent forward-progress/capacity exercise.
    recovery_checker.arm_recovery(IBI_ERR_OVERFLOW, 1'b0, 1'b0);
    reset_target_ibi_queue(ral);
    expect_field(ral.I3C_EC.TTI.QUEUE_STATUS.IBI_QUEUE_EMPTY, 1,
                 {operation, ": confirm empty queue after recovery"});
    recovery_checker.wait_for_result(
      vseq_ctx.cfg.ibi_timeout_cycles,
      recovery_completed, recovery_passed);
    if (!recovery_completed || !recovery_passed)
      `uvm_fatal("IBI_TARGET_OVERFLOW_RECOVERY",
                 $sformatf("%s did not complete checked overflow recovery",
                           operation))
  endtask

  protected task run_target_tti_overflow(input i3c_ral_model ral);
    initialize_target_ibi(ral);
    write_field(ral.I3C_EC.TTI.CONTROL.IBI_EN, 0,
                "disable Target IBI transmission while filling TTI queue");

    fill_and_overflow_target_queue(
      ral, 1'b0, "Target TTI descriptor overflow");
    fill_and_overflow_target_queue(
      ral, 1'b1, "Target TTI payload-data overflow");
    `uvm_info("IBI_OVERFLOW_TARGET",
              $sformatf("PASS: Target-TX combined TTI IBI FIFO capacity=%0d DWORDs; excess writes in descriptor-role and payload-role phases left depth, write pointer, and retained storage unchanged",
                        vseq_ctx.cfg.ibi_queue_size),
              UVM_LOW)
  endtask

`endif
`endif

  virtual task body();
    super.body();
    if (!vseq_ctx.cfg.has_rtl)
      `uvm_fatal("IBI_OVERFLOW_MODE",
                 "i3c_ibi_target_tx_overflow_test requires native I3C RTL mode")

`ifdef I3C_DV_NATIVE_RTL
`ifdef I3C_DV_NATIVE_RAL
    if (vseq_ctx.cfg.ibi_dut_role == I3C_IBI_DUT_TARGET) begin
      `uvm_info("IBI_OVERFLOW_DOMAIN",
                "Running DUT Target-TX combined-TTI overflow scenario",
                UVM_LOW)
      run_target_tti_overflow(get_i3c_ral_model());
    end else
      `uvm_fatal("IBI_OVERFLOW_SEQUENCE_ROLE",
                 "i3c_ibi_target_tx_overflow_vseq requires DUT Target-TX role")
`else
    `uvm_fatal("IBI_OVERFLOW_RAL_BUILD",
               "i3c_ibi_target_tx_overflow_test requires I3C_DV_NATIVE_RAL")
`endif
`else
    `uvm_fatal("IBI_OVERFLOW_RTL_BUILD",
               "i3c_ibi_target_tx_overflow_test requires I3C_DV_NATIVE_RTL")
`endif
  endtask
endclass : i3c_ibi_target_tx_overflow_vseq

`endif // I3C_IBI_TARGET_TX_OVERFLOW_VSEQ_SV
