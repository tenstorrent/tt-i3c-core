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
// File        : i3c_ibi_controller_rx_fifo_irq_vseq.sv
// Description : Controller-RX IBI FIFO threshold and IRQ virtual sequence.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-04
//
// *****************************************************************************

`ifndef I3C_IBI_CONTROLLER_RX_FIFO_IRQ_VSEQ_SV
`define I3C_IBI_CONTROLLER_RX_FIFO_IRQ_VSEQ_SV

class i3c_ibi_controller_rx_fifo_irq_vseq extends i3c_ibi_base_vseq;
  `uvm_object_utils(i3c_ibi_controller_rx_fifo_irq_vseq)

  // The reviewed native RTL applies this threshold to IBI_PORT DWORD occupancy. Each
  // record in this test consumes one descriptor plus one aligned data DWORD,
  // so 3 separates the first record (level 2) from two records (level 4).
  localparam int unsigned IBI_STATUS_THRESHOLD = 3;
  localparam int unsigned RECORD_COUNT = 2;
  localparam int unsigned DWORDS_PER_ACCEPTED_RECORD = 2;
  localparam int unsigned IRQ_QUIET_CYCLES = 32;

  function new(string name = "i3c_ibi_controller_rx_fifo_irq_vseq");
    super.new(name);
  endfunction

`ifdef I3C_DV_NATIVE_RTL
`ifdef I3C_DV_NATIVE_RAL
  protected task expect_irq_quiet(input string operation);
    repeat (IRQ_QUIET_CYCLES) begin
      if (vseq_ctx.cfg.vif.i3c_irq !== 1'b0)
        `uvm_fatal("IBI_CTRL_FIFO_IRQ_MASK",
                   $sformatf("%s: IRQ asserted while it must remain low",
                             operation))
      @(posedge vseq_ctx.cfg.vif.clk);
    end
  endtask

  protected task wait_target_armed(input uvm_event armed_event,
                                   input string operation);
    bit armed;

    armed = 1'b0;
    fork : armed_guard
      begin
        armed_event.wait_on();
        armed = 1'b1;
      end
      begin
        repeat (vseq_ctx.cfg.ibi_timeout_cycles)
          @(posedge vseq_ctx.cfg.vif.clk);
      end
    join_any
    disable armed_guard;
    if (!armed)
      `uvm_fatal("IBI_CTRL_FIFO_ARM_TIMEOUT",
                 $sformatf("%s: target IBI did not arm", operation))
  endtask

  protected task wait_target_done(ref bit done,
                                  input string operation);
    if (done)
      return;
    repeat (vseq_ctx.cfg.ibi_timeout_cycles) begin
      @(posedge vseq_ctx.cfg.vif.clk);
      if (done)
        return;
    end
    `uvm_fatal("IBI_CTRL_FIFO_BUS_TIMEOUT",
               $sformatf("%s: target IBI did not complete", operation))
  endtask

  protected task send_ibi(
      input int unsigned sequence_index,
      input bit expected_ack,
      input i3c_controller_hci_helper #(
        TB_ADDR_WIDTH, TB_DATA_WIDTH) hci_helper);
    i3c_target_send_ibi_seq target_seq;
    uvm_event target_armed_event;
    bit target_done;
    string operation;

    operation = $sformatf("Controller FIFO IBI[%0d]", sequence_index);
    wait_bus_idle({operation, ": wait for idle bus"});
    hci_helper.wait_bus_available(this);

    target_seq = i3c_target_send_ibi_seq::type_id::create(
      $sformatf("target_seq_%0d", sequence_index));
    target_seq.target_addr = vseq_ctx.cfg.ibi_target_addr;
    target_seq.mdb_present = 1'b1;
    target_seq.mdb = 8'ha0 + sequence_index[7:0];
    target_seq.payload.push_back(sequence_index[7:0]);
    target_seq.payload.push_back(~sequence_index[7:0]);
    target_seq.start_on_idle = 1'b0;

    target_done = 1'b0;
    target_armed_event = uvm_event_pool::get_global(
      I3C_TARGET_IBI_ARMED_EVENT);
    target_armed_event.reset();
    vseq_ctx.cfg.ibi_controller_attempt_cases++;
    vseq_ctx.cfg.vif.i3c_controller_expected_ack = expected_ack;
    fork : target_driver
      begin
        target_seq.start(vseq_ctx.i3c_sqr);
        target_done = 1'b1;
      end
    join_none

    wait_target_armed(target_armed_event, operation);
    vseq_ctx.cfg.ibi_bus_state = 2'd1;
    hci_helper.issue_dat_private_write(
      vseq_ctx.cfg.ibi_controller_dat_index,
      8'hc0 + sequence_index[7:0],
      sequence_index[3:0] + 1'b1,
      this);
    wait_target_done(target_done, operation);
    disable target_driver;
    if (target_seq.observed_ack !== expected_ack)
      `uvm_fatal("IBI_CTRL_FIFO_RESPONSE",
                 $sformatf("%s expected ACK=%0b actual=%0b",
                           operation, expected_ack,
                           target_seq.observed_ack))
  endtask

  protected task check_nack_record(input bit [31:0] descriptor,
                                   input byte unsigned data[$]);
    if (descriptor[15:8] !== {vseq_ctx.cfg.ibi_target_addr, 1'b1})
      `uvm_fatal("IBI_CTRL_FIFO_NACK_ID",
                 $sformatf("full-queue NACK expected IBI_ID=0x%02h actual=0x%02h",
                           {vseq_ctx.cfg.ibi_target_addr, 1'b1},
                           descriptor[15:8]))
    if ((descriptor[31] !== 1'b1) ||
        (descriptor[30] !== 1'b0) ||
        (descriptor[29:27] !== 3'b000) ||
        (descriptor[24] !== 1'b1) ||
        (descriptor[7:0] !== 8'd0) ||
        (data.size() != 0))
      `uvm_fatal("IBI_CTRL_FIFO_NACK_DESCRIPTOR",
                 $sformatf("full-queue NACK returned invalid descriptor=0x%08h data=%0d",
                           descriptor, data.size()))
  endtask

  protected task check_record(input int unsigned sequence_index,
                              input bit [31:0] descriptor,
                              input byte unsigned data[$]);
    bit [7:0] expected_mdb;
    bit [7:0] expected_payload0;
    bit [7:0] expected_payload1;

    expected_mdb = 8'ha0 + sequence_index[7:0];
    expected_payload0 = sequence_index[7:0];
    expected_payload1 = ~sequence_index[7:0];
    if (descriptor[15:8] !== {vseq_ctx.cfg.ibi_target_addr, 1'b1})
      `uvm_fatal("IBI_CTRL_FIFO_ID",
                 $sformatf("record[%0d] expected IBI_ID=0x%02h actual=0x%02h",
                           sequence_index,
                           {vseq_ctx.cfg.ibi_target_addr, 1'b1},
                           descriptor[15:8]))
    if ((descriptor[31:30] !== 2'b00) ||
        (descriptor[29:27] !== 3'b000) ||
        (descriptor[24] !== 1'b1))
      `uvm_fatal("IBI_CTRL_FIFO_DESCRIPTOR",
                 $sformatf("record[%0d] has invalid status descriptor 0x%08h",
                           sequence_index, descriptor))
    if ((descriptor[7:0] !== 8'd3) || (data.size() != 3))
      `uvm_fatal("IBI_CTRL_FIFO_LENGTH",
                 $sformatf("record[%0d] expected 3 bytes, descriptor=0x%08h data=%0d",
                           sequence_index, descriptor, data.size()))
    if ((data[0] !== expected_mdb) ||
        (data[1] !== expected_payload0) ||
        (data[2] !== expected_payload1))
      `uvm_fatal("IBI_CTRL_FIFO_ORDER",
                 $sformatf("record[%0d] expected=%02h_%02h_%02h actual=%02h_%02h_%02h",
                           sequence_index, expected_mdb, expected_payload0,
                           expected_payload1, data[0], data[1], data[2]))
  endtask
`endif
`endif

  virtual task body();
    super.body();
    if (!vseq_ctx.cfg.has_rtl)
      `uvm_fatal("IBI_CTRL_FIFO_MODE",
                 "Controller FIFO/IRQ test requires native I3C RTL mode")
    if (vseq_ctx.cfg.ibi_dut_role != I3C_IBI_DUT_CONTROLLER)
      `uvm_fatal("IBI_CTRL_FIFO_ROLE",
                 "Controller FIFO/IRQ vseq requires DUT-controller role")

`ifdef I3C_DV_NATIVE_RTL
`ifdef I3C_DV_NATIVE_RAL
    begin
      i3c_controller_hci_helper #(TB_ADDR_WIDTH, TB_DATA_WIDTH)
        hci_helper;
      uvm_reg_data_t queue_size;
      uvm_reg_data_t ext_queue_enable;
      bit [31:0] interrupt_status;
      bit [31:0] descriptor;
      byte unsigned hci_data[$];
      int unsigned effective_queue_depth;
      int unsigned full_record_count;
      int unsigned expected_total_records;
      int unsigned completion_before;
      int unsigned expected_before;
      int unsigned actual_before;
      int unsigned mismatch_before;
      int unsigned irq_events_before;
      bit record_irq_required_before;

      hci_helper = vseq_ctx.i3c_controller_hci_helper;
      if (hci_helper == null)
        `uvm_fatal("IBI_CTRL_FIFO_HELPER",
                   "Controller HCI helper is not available")

      completion_before = vseq_ctx.cfg.ibi_sb_completion_count;
      expected_before = vseq_ctx.cfg.ibi_controller_expected_events;
      actual_before = vseq_ctx.cfg.ibi_controller_actual_events;
      mismatch_before = vseq_ctx.cfg.ibi_sb_mismatch_count;
      irq_events_before = vseq_ctx.cfg.ibi_controller_irq_events;
      record_irq_required_before =
        vseq_ctx.cfg.require_ibi_controller_record_irq;
      // IBI_STATUS_THLD is queue-level evidence: one coalesced assertion can
      // cover several records. Record content remains checked through the
      // HCI, target and passive-monitor correlation paths.
      vseq_ctx.cfg.require_ibi_controller_record_irq = 1'b0;

      hci_helper.initialize_controller_ibi(
        vseq_ctx.cfg.ibi_target_addr,
        vseq_ctx.cfg.ibi_controller_dat_index,
        this);
      read_field(vseq_ctx.cfg.ral_model.PIOControl.QUEUE_SIZE.IBI_STATUS_SIZE,
                 queue_size, "read Controller IBI status queue size");
      read_field(vseq_ctx.cfg.ral_model.PIOControl.ALT_QUEUE_SIZE.EXT_IBI_QUEUE_EN,
                 ext_queue_enable, "read extended IBI queue enable");
      effective_queue_depth = queue_size[7:0] *
        (ext_queue_enable[0] ? 8 : 1);
      if (effective_queue_depth < IBI_STATUS_THRESHOLD)
        `uvm_fatal("IBI_CTRL_FIFO_DEPTH",
                   $sformatf("IBI queue depth %0d is below threshold %0d",
                             effective_queue_depth,
                             IBI_STATUS_THRESHOLD))
      if ((effective_queue_depth > 255) ||
          ((effective_queue_depth % DWORDS_PER_ACCEPTED_RECORD) != 0))
        `uvm_fatal("IBI_CTRL_FIFO_DEPTH_LAYOUT",
                   $sformatf("IBI queue depth %0d cannot be covered by %0d-DWORD records and an 8-bit threshold",
                             effective_queue_depth,
                             DWORDS_PER_ACCEPTED_RECORD))

      write_field(
        vseq_ctx.cfg.ral_model.PIOControl.QUEUE_THLD_CTRL.IBI_STATUS_THLD,
        IBI_STATUS_THRESHOLD, "set Controller IBI status threshold");
      expect_field(
        vseq_ctx.cfg.ral_model.PIOControl.QUEUE_THLD_CTRL.IBI_STATUS_THLD,
        IBI_STATUS_THRESHOLD, "verify Controller IBI status threshold");
      write_field(
        vseq_ctx.cfg.ral_model.PIOControl.PIO_INTR_STATUS_ENABLE.IBI_STATUS_THLD_STAT_EN,
        1, "enable Controller IBI threshold status");
      write_field(
        vseq_ctx.cfg.ral_model.PIOControl.PIO_INTR_SIGNAL_ENABLE.IBI_STATUS_THLD_SIGNAL_EN,
        0, "mask Controller IBI threshold signal");

      wait_irq(1'b0, "verify Controller IBI IRQ initially low");
      hci_helper.enable_broadcast_header(this);

      send_ibi(0, 1'b1, hci_helper);
      hci_helper.read_ibi_status(interrupt_status, this);
      if (interrupt_status[2])
        `uvm_fatal("IBI_CTRL_FIFO_BELOW_THLD",
                   $sformatf("threshold status asserted at FIFO level 2 below threshold %0d: 0x%08h",
                             IBI_STATUS_THRESHOLD, interrupt_status))
      expect_irq_quiet("below threshold");

      // This is also the forward-progress gate for the known post-IBI RTL
      // issue. A fixed DUT must accept the second IBI without draining the
      // first record.
      send_ibi(1, 1'b1, hci_helper);
      wait_field_value(
        vseq_ctx.cfg.ral_model.PIOControl.PIO_INTR_STATUS.IBI_STATUS_THLD_STAT,
        1, "wait for Controller IBI threshold status");
      expect_irq_quiet("threshold reached while signal is masked");

      write_field(
        vseq_ctx.cfg.ral_model.PIOControl.PIO_INTR_SIGNAL_ENABLE.IBI_STATUS_THLD_SIGNAL_EN,
        1, "unmask Controller IBI threshold signal");
      wait_irq(1'b1, "wait for coalesced Controller IBI threshold IRQ");
      if ((vseq_ctx.cfg.ibi_controller_irq_events - irq_events_before) != 1)
        `uvm_fatal("IBI_CTRL_FIFO_IRQ_COUNT",
                   $sformatf("expected one coalesced IRQ edge in FIFO phase, got delta=%0d total=%0d baseline=%0d",
                             vseq_ctx.cfg.ibi_controller_irq_events -
                             irq_events_before,
                             vseq_ctx.cfg.ibi_controller_irq_events,
                             irq_events_before))

      hci_helper.read_ibi_record(descriptor, hci_data, this);
      check_record(0, descriptor, hci_data);
      wait_scoreboard_completion(completion_before + 1,
                                 "wait for first FIFO record scoreboard completion");
      wait_field_value(
        vseq_ctx.cfg.ral_model.PIOControl.PIO_INTR_STATUS.IBI_STATUS_THLD_STAT,
        0, "wait for threshold status clear below threshold");
      wait_irq(1'b0, "wait for IRQ clear below threshold");

      hci_helper.read_ibi_record(descriptor, hci_data, this);
      check_record(1, descriptor, hci_data);
      wait_scoreboard_completion(completion_before + RECORD_COUNT,
                                 "wait for all FIFO records scoreboard completion");

      hci_helper.read_ibi_status(interrupt_status, this);
      if (interrupt_status[2])
        `uvm_fatal("IBI_CTRL_FIFO_DRAIN",
                   $sformatf("threshold status remained set after drain: 0x%08h",
                             interrupt_status))

      // Fill every Controller IBI-port DWORD without draining. The unique
      // sequence content lets both the direct checker and scoreboard detect
      // loss, duplication or reordering across pointer wrap.
      full_record_count = effective_queue_depth /
        DWORDS_PER_ACCEPTED_RECORD;
      write_field(
        vseq_ctx.cfg.ral_model.PIOControl.QUEUE_THLD_CTRL.IBI_STATUS_THLD,
        effective_queue_depth, "set full-queue IBI threshold");
      for (int unsigned index = 0; index < full_record_count; index++) begin
        send_ibi(index + RECORD_COUNT, 1'b1, hci_helper);
        if (index != (full_record_count - 1))
          expect_irq_quiet(
            $sformatf("fill below full level after record %0d", index));
      end
      wait_field_value(
        vseq_ctx.cfg.ral_model.PIOControl.PIO_INTR_STATUS.IBI_STATUS_THLD_STAT,
        1, "wait for full-queue threshold status");
      wait_irq(1'b1, "wait for full-queue threshold IRQ");

      // With no descriptor DWORD available, the next real requester must be
      // NACKed. Its zero-length status descriptor cannot be committed until
      // software drains at least one DWORD from the full queue.
      vseq_ctx.cfg.ibi_controller_fifo_full_expected_nack = 1'b1;
      send_ibi(RECORD_COUNT + full_record_count, 1'b0, hci_helper);
      vseq_ctx.cfg.ibi_controller_fifo_full_expected_nack = 1'b0;
      vseq_ctx.cfg.vif.i3c_controller_expected_ack = 1'b1;

      for (int unsigned index = 0; index < full_record_count; index++) begin
        hci_helper.read_ibi_record(descriptor, hci_data, this);
        check_record(index + RECORD_COUNT, descriptor, hci_data);
        wait_scoreboard_completion(
          completion_before + RECORD_COUNT + index + 1,
          $sformatf("wait for full FIFO record[%0d] scoreboard completion",
                    index));
        if (index == 0) begin
          wait_field_value(
            vseq_ctx.cfg.ral_model.PIOControl.PIO_INTR_STATUS.IBI_STATUS_THLD_STAT,
            0, "wait for full threshold clear after first drain");
          wait_irq(1'b0, "wait for full-queue IRQ clear after first drain");
        end
      end

      hci_helper.read_ibi_record(descriptor, hci_data, this);
      check_nack_record(descriptor, hci_data);
      expected_total_records = RECORD_COUNT + full_record_count + 1;
      wait_scoreboard_completion(
        completion_before + expected_total_records,
        "wait for full-queue NACK descriptor scoreboard completion");

      // IBI_STATUS_THLD_STAT is a non-sticky level status and therefore is
      // not W1C. Exercise W1C on the PIO transfer-error interrupt, which is
      // the W1C source in this register block, after FIFO closure is complete.
      write_field(
        vseq_ctx.cfg.ral_model.PIOControl.PIO_INTR_STATUS_ENABLE.TRANSFER_ERR_STAT_EN,
        1, "enable forced PIO transfer-error status");
      write_field(
        vseq_ctx.cfg.ral_model.PIOControl.PIO_INTR_SIGNAL_ENABLE.TRANSFER_ERR_SIGNAL_EN,
        1, "enable forced PIO transfer-error signal");
      write_field(
        vseq_ctx.cfg.ral_model.PIOControl.PIO_INTR_FORCE.TRANSFER_ERR_FORCE,
        1, "force PIO transfer-error interrupt");
      wait_field_value(
        vseq_ctx.cfg.ral_model.PIOControl.PIO_INTR_STATUS.TRANSFER_ERR_STAT,
        1, "wait for forced PIO transfer-error status");
      wait_irq(1'b1, "wait for forced PIO transfer-error IRQ");
      write_field(
        vseq_ctx.cfg.ral_model.PIOControl.PIO_INTR_FORCE.TRANSFER_ERR_FORCE,
        0, "release PIO transfer-error force");
      write_field(
        vseq_ctx.cfg.ral_model.PIOControl.PIO_INTR_STATUS.TRANSFER_ERR_STAT,
        1, "W1C clear PIO transfer-error status");
      wait_field_value(
        vseq_ctx.cfg.ral_model.PIOControl.PIO_INTR_STATUS.TRANSFER_ERR_STAT,
        0, "wait for PIO transfer-error W1C clear");
      wait_irq(1'b0, "wait for forced PIO transfer-error IRQ clear");

      if (((vseq_ctx.cfg.ibi_controller_expected_events - expected_before) !=
             expected_total_records) ||
          ((vseq_ctx.cfg.ibi_controller_actual_events - actual_before) !=
             expected_total_records))
        `uvm_fatal("IBI_CTRL_FIFO_EVENT_COUNT",
                   $sformatf("expected/actual Controller events must be %0d/%0d, got %0d/%0d",
                             expected_total_records,
                             expected_total_records,
                             vseq_ctx.cfg.ibi_controller_expected_events,
                             vseq_ctx.cfg.ibi_controller_actual_events))
      if (vseq_ctx.cfg.ibi_sb_mismatch_count != mismatch_before)
        `uvm_error("IBI_CTRL_FIFO_SB",
                   $sformatf("Controller FIFO added scoreboard mismatches=%0d",
                             vseq_ctx.cfg.ibi_sb_mismatch_count -
                             mismatch_before))

      vseq_ctx.cfg.require_ibi_controller_record_irq =
        record_irq_required_before;

      `uvm_info("IBI_CTRL_FIFO_IRQ",
                $sformatf("PASS: depth=%0d threshold=%0d records=%0d ordered; full/NACK, mask/coalesced IRQ and W1C checked",
                          effective_queue_depth, IBI_STATUS_THRESHOLD,
                          expected_total_records),
                UVM_LOW)
    end
`else
    `uvm_fatal("IBI_CTRL_FIFO_RAL_BUILD",
               "Controller FIFO/IRQ test requires I3C_DV_NATIVE_RAL")
`endif
`else
    `uvm_fatal("IBI_CTRL_FIFO_RTL_BUILD",
               "Controller FIFO/IRQ test requires I3C_DV_NATIVE_RTL")
`endif
  endtask
endclass : i3c_ibi_controller_rx_fifo_irq_vseq

`endif // I3C_IBI_CONTROLLER_RX_FIFO_IRQ_VSEQ_SV
