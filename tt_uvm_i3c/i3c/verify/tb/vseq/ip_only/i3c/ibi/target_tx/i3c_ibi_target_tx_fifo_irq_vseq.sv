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
// File        : i3c_ibi_target_tx_fifo_irq_vseq.sv
// Description : Virtual sequence for I3C IBI FIFO IRQ.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-24
//
// *****************************************************************************

`ifndef I3C_IBI_TARGET_TX_FIFO_IRQ_VSEQ_SV
`define I3C_IBI_TARGET_TX_FIFO_IRQ_VSEQ_SV

class i3c_ibi_target_tx_fifo_irq_vseq extends i3c_ibi_base_vseq;
  `uvm_object_utils(i3c_ibi_target_tx_fifo_irq_vseq)

  localparam int unsigned MAX_RECORD_DWORDS = 4;

  function new(string name = "i3c_ibi_target_tx_fifo_irq_vseq");
    super.new(name);
  endfunction

`ifdef I3C_DV_NATIVE_RTL
`ifdef I3C_DV_NATIVE_RAL
  protected function byte unsigned payload_byte(int unsigned record_index,
                                                int unsigned byte_index);
    byte unsigned value;

    value = (record_index * 8'h20) + byte_index;
    return value;
  endfunction

  protected function int unsigned payload_len_for_words(
      int unsigned payload_words);
    if (payload_words == 0)
      return 0;
    // Use at least one byte in the final DWORD so ceil(len/4) is exact.
    return (4 * (payload_words - 1)) + 1;
  endfunction

  protected task observe_queue_growth(
      input i3c_ral_model ral,
      input int unsigned previous_depth,
      output int unsigned observed_depth,
      input string operation);
    uvm_reg_data_t depth_value;

    for (int unsigned cycle = 0;
         cycle < vseq_ctx.cfg.ibi_timeout_cycles; cycle++) begin
      read_field(ral.I3C_EC.TTI.IBI_QUEUE_DEPTH.IBI_QUEUE_DEPTH,
                 depth_value, operation);
      observed_depth = int'(depth_value);
      if ((observed_depth > previous_depth) &&
          (observed_depth <= vseq_ctx.cfg.ibi_queue_size))
        return;
      @(posedge vseq_ctx.cfg.vif.clk);
    end
    `uvm_fatal(
      "IBI_QUEUE_GROWTH_TIMEOUT",
      $sformatf("%s: depth did not grow from %0d within capacity %0d",
                operation, previous_depth, vseq_ctx.cfg.ibi_queue_size))
  endtask

  protected task queue_ibi_record(
      input i3c_ral_model ral,
      input i3c_host_respond_ibi_burst_seq host_seq,
      input int unsigned record_index,
      input int unsigned record_dwords);
    uvm_reg_data_t descriptor;
    uvm_reg_data_t payload_word;
    byte unsigned mdb;
    int unsigned payload_words;
    int unsigned payload_len;

    if ((record_dwords == 0) || (record_dwords > MAX_RECORD_DWORDS))
      `uvm_fatal("IBI_FIFO_RECORD",
                 $sformatf("Invalid record size %0d DWORDs", record_dwords))

    payload_words = record_dwords - 1;
    payload_len = payload_len_for_words(payload_words);
    mdb = vseq_ctx.cfg.ibi_basic_mdb + record_index[7:0];
    descriptor = (uvm_reg_data_t'(mdb) << 24) |
                 uvm_reg_data_t'(payload_len[7:0]);

    host_seq.rx_byte_count_q.push_back(payload_len + 1);
    host_seq.ibi_ack_q.push_back(1'b1);
    write_register(
      ral.I3C_EC.TTI.IBI_PORT, descriptor,
      $sformatf("queue FIFO record %0d descriptor MDB=0x%02h payload=%0d",
                record_index, mdb, payload_len));

    for (int unsigned word_index = 0;
         word_index < payload_words; word_index++) begin
      payload_word = '0;
      for (int unsigned lane = 0; lane < 4; lane++) begin
        int unsigned flat_index;

        flat_index = (word_index * 4) + lane;
        if (flat_index < payload_len)
          payload_word[8*lane +: 8] =
            payload_byte(record_index, flat_index);
      end
      write_register(
        ral.I3C_EC.TTI.IBI_PORT, payload_word,
        $sformatf("queue FIFO record %0d payload word %0d",
                  record_index, word_index));
    end
  endtask

  protected task fill_ibi_fifo(
      input i3c_ral_model ral,
      input i3c_host_respond_ibi_burst_seq host_seq,
      input int unsigned record_index_base,
      output int unsigned record_count);
    int unsigned current_depth;
    int unsigned remaining_dwords;
    int unsigned record_dwords;
    int unsigned previous_depth;

    record_count = 0;
    current_depth = 0;

    // The current core may prefetch the first descriptor while IBI_EN is low.
    // Observe the resulting architectural depth rather than assuming whether
    // that descriptor remains in the FIFO.
    record_dwords = (vseq_ctx.cfg.ibi_queue_size >
                     MAX_RECORD_DWORDS) ?
                    MAX_RECORD_DWORDS :
                    vseq_ctx.cfg.ibi_queue_size;
    queue_ibi_record(ral, host_seq, record_index_base + record_count,
                     record_dwords);
    record_count++;
    observe_queue_growth(
      ral, 0, current_depth,
      "observe FIFO depth after first record and optional descriptor prefetch");

    while (current_depth < vseq_ctx.cfg.ibi_queue_size) begin
      remaining_dwords = vseq_ctx.cfg.ibi_queue_size - current_depth;
      record_dwords = (remaining_dwords > MAX_RECORD_DWORDS) ?
                      MAX_RECORD_DWORDS : remaining_dwords;
      previous_depth = current_depth;
      queue_ibi_record(ral, host_seq, record_index_base + record_count,
                       record_dwords);
      record_count++;
      observe_queue_growth(
        ral, previous_depth, current_depth,
        $sformatf("observe FIFO fill depth after record %0d",
                  record_index_base + record_count - 1));
    end
  endtask

  protected task drain_ibi_fifo(
      input i3c_ral_model ral,
      input uvm_event host_armed_event,
      input uvm_event host_detected_event,
      input int unsigned record_count,
      input int unsigned completion_before,
      input int unsigned mismatch_before,
      input bit check_threshold,
      input int unsigned threshold_entries,
      output bit threshold_seen);
    uvm_reg_data_t terminal_status;
    uvm_reg_data_t depth_value;
    uvm_reg_data_t threshold_status;
    int unsigned current_depth;
    int unsigned previous_depth;
    int unsigned free_entries;

    threshold_seen = 1'b0;
    previous_depth = vseq_ctx.cfg.ibi_queue_size;
    for (int unsigned index = 0; index < record_count; index++) begin
      if ((index + 1) < record_count) begin
        // Stop automatic dequeue of the following record while the current
        // IBI is still transferring. Waiting until IBI_DONE is too late:
        // LAST_IBI_STATUS is shared and the next record can overwrite it.
        host_detected_event.wait_on();
        host_detected_event.reset();
        write_field(
          ral.I3C_EC.TTI.CONTROL.IBI_EN, 0,
          $sformatf("pause after controller detected FIFO record %0d",
                    index));
      end

      wait_field_value(
        ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 1,
        $sformatf("wait for record %0d IBI_DONE", index));
      if (vseq_ctx.cfg.vif.i3c_irq !== 1'b1)
        `uvm_fatal("IBI_DONE_IRQ",
                   $sformatf("IBI_DONE for record %0d did not assert i3c_irq",
                             index))

      // Capture LAST_IBI_STATUS immediately. A later IBI may overwrite this
      // single architectural status field, so no AXI control write may be
      // inserted between observing IBI_DONE and reading the status.
      read_field(ral.I3C_EC.TTI.STATUS.LAST_IBI_STATUS, terminal_status,
                 $sformatf("capture record %0d LAST_IBI_STATUS", index));
      if (terminal_status != uvm_reg_data_t'(IBI_STATUS_SUCCESS))
        `uvm_fatal("IBI_TERMINAL_STATUS",
                   $sformatf("Record %0d expected SUCCESS, actual=0x%0h",
                             index, terminal_status))

      wait_scoreboard_completion(
        completion_before + index + 1,
        $sformatf("wait for record %0d scoreboard result", index));
      if (vseq_ctx.cfg.ibi_sb_mismatch_count != mismatch_before)
        `uvm_fatal(
          "IBI_SCOREBOARD_CHECK",
           $sformatf("FIFO drain added %0d scoreboard mismatch(es)",
                     vseq_ctx.cfg.ibi_sb_mismatch_count - mismatch_before))

      read_field(ral.I3C_EC.TTI.IBI_QUEUE_DEPTH.IBI_QUEUE_DEPTH,
                 depth_value,
                 $sformatf("observe FIFO depth after record %0d", index));
      current_depth = int'(depth_value);
      if (current_depth > previous_depth)
        `uvm_fatal(
          "IBI_FIFO_DRAIN_DEPTH",
          $sformatf("Record %0d increased FIFO depth from %0d to %0d",
                    index, previous_depth, current_depth))
      if (current_depth > vseq_ctx.cfg.ibi_queue_size)
        `uvm_fatal(
          "IBI_FIFO_DRAIN_DEPTH",
          $sformatf("Record %0d observed depth %0d above capacity %0d",
                    index, current_depth, vseq_ctx.cfg.ibi_queue_size))
      previous_depth = current_depth;

      if (check_threshold) begin
        free_entries = vseq_ctx.cfg.ibi_queue_size - current_depth;
        if (free_entries < threshold_entries) begin
          read_field(
            ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_THLD_STAT,
            threshold_status,
            $sformatf("check threshold remains low after record %0d", index));
          if (threshold_status != 0)
            `uvm_fatal(
              "IBI_THRESHOLD_EARLY",
              $sformatf("Threshold asserted early after record %0d: free=%0d threshold=%0d depth=%0d",
                        index, free_entries, threshold_entries, current_depth))
          wait_irq(
            1'b0,
            $sformatf("check no threshold IRQ below boundary after record %0d",
                      index));
        end else begin
          wait_field_value(
            ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_THLD_STAT, 1,
            $sformatf("wait for threshold crossing after record %0d", index));
          threshold_seen = 1'b1;
          if (vseq_ctx.cfg.vif.i3c_irq !== 1'b1)
            `uvm_fatal(
              "IBI_THRESHOLD_IRQ",
              $sformatf("Threshold status lacks IRQ after record %0d: free=%0d threshold=%0d",
                        index, free_entries, threshold_entries))
        end
      end

      if ((index + 1) < record_count) begin
        // The burst sequence publishes this event for every response item.
        // Do not release the next descriptor until the controller is waiting.
        host_armed_event.wait_on();
        host_armed_event.reset();
        write_field(
          ral.I3C_EC.TTI.CONTROL.IBI_EN, 1,
          $sformatf("release FIFO record %0d after boundary checks",
                    index + 1));
      end
    end

    if (check_threshold && !threshold_seen)
      `uvm_fatal(
        "IBI_THRESHOLD_NOT_REACHED",
        $sformatf("Draining %0d records never reached threshold %0d",
                  record_count, threshold_entries))
  endtask

  protected task run_host_drain(
      input i3c_ral_model ral,
      input i3c_host_respond_ibi_burst_seq host_seq,
      input int unsigned record_count,
      input int unsigned completion_before,
      input int unsigned mismatch_before,
      input bit check_threshold,
      input int unsigned threshold_entries,
      output bit threshold_seen);
    uvm_event host_armed_event;
    uvm_event host_detected_event;
    bit drain_done;

    host_armed_event = uvm_event_pool::get_global(
      I3C_HOST_IBI_ARMED_EVENT);
    host_detected_event = uvm_event_pool::get_global(
      I3C_HOST_IBI_DETECTED_EVENT);
    host_armed_event.reset();
    host_detected_event.reset();
    drain_done = 1'b0;

    fork : fifo_drain_timeout_guard
      begin
        fork
          host_seq.start(vseq_ctx.i3c_sqr);
          begin
            host_armed_event.wait_on();
            host_armed_event.reset();
            write_field(ral.I3C_EC.TTI.CONTROL.IBI_EN, 1,
                        "release queued IBI records for transmission");
            drain_ibi_fifo(ral, host_armed_event, host_detected_event,
                           record_count, completion_before, mismatch_before,
                           check_threshold, threshold_entries, threshold_seen);
          end
        join
        drain_done = 1'b1;
      end
      begin
        repeat (vseq_ctx.cfg.ibi_timeout_cycles)
          @(posedge vseq_ctx.cfg.vif.clk);
        if (!drain_done)
          `uvm_fatal("IBI_FIFO_IRQ_TIMEOUT",
                     $sformatf("Timed out draining %0d queued IBI records",
                               record_count))
      end
    join_any
    disable fifo_drain_timeout_guard;

    if (!drain_done || (host_seq.response_count != record_count))
      `uvm_fatal(
        "IBI_FIFO_HOST_CHECK",
        $sformatf("Expected %0d host responses, observed %0d drain_done=%0b",
                  record_count, host_seq.response_count, drain_done))
  endtask
`endif
`endif

  virtual task body();
    super.body();

    if (!vseq_ctx.cfg.has_rtl)
      `uvm_fatal("I3C_MODE",
                 "i3c_ibi_target_tx_fifo_irq_test requires native I3C RTL mode")
    if (vseq_ctx.cfg.ibi_dut_role != I3C_IBI_DUT_TARGET)
      `uvm_fatal("IBI_FIFO_IRQ_ROLE",
                 "i3c_ibi_target_tx_fifo_irq_test covers DUT-target transmit only")
`ifndef I3C_DV_NATIVE_RTL
    `uvm_fatal("IBI_VIP_BUILD",
               "I3C host VIP is available only in native I3C RTL mode")
`elsif I3C_DV_NATIVE_RAL
    begin
      i3c_ral_model ral;
      i3c_host_respond_ibi_burst_seq host_seq;
      i3c_host_respond_ibi_burst_seq refill_host_seq;
      int unsigned record_count;
      int unsigned refill_record_count;
      int unsigned total_record_count;
      int unsigned threshold_entries;
      int unsigned completion_before;
      int unsigned mismatch_before;
      int unsigned attempt_samples_before;
      int unsigned completion_samples_before;
      int unsigned queue_irq_samples_before;
      int unsigned threshold_below_samples_before;
      int unsigned threshold_reached_samples_before;
      int unsigned attempt_samples;
      int unsigned completion_samples;
      int unsigned queue_irq_samples;
      int unsigned threshold_below_samples;
      int unsigned threshold_reached_samples;
      bit threshold_seen;
      bit refill_threshold_seen;

      if (vseq_ctx.i3c_sqr == null)
        `uvm_fatal("IBI_HOST_SQR", "I3C host sequencer is not available")
      if (!vseq_ctx.cfg.has_ibi_scoreboard)
        `uvm_fatal("IBI_SCOREBOARD_CFG",
                   "FIFO/IRQ test requires the IBI scoreboard")

      ral = get_i3c_ral_model();
      completion_before = vseq_ctx.cfg.ibi_sb_completion_count;
      mismatch_before = vseq_ctx.cfg.ibi_sb_mismatch_count;
      attempt_samples_before = vseq_ctx.cfg.ibi_cov_attempt_samples;
      completion_samples_before = vseq_ctx.cfg.ibi_cov_completion_samples;
      queue_irq_samples_before = vseq_ctx.cfg.ibi_cov_queue_irq_samples;
      threshold_below_samples_before =
        vseq_ctx.cfg.ibi_cov_threshold_below_samples;
      threshold_reached_samples_before =
        vseq_ctx.cfg.ibi_cov_threshold_reached_samples;

      initialize_target_ibi(ral);
      write_field(ral.I3C_EC.TTI.CONTROL.IBI_EN, 0,
                  "hold DUT target IBI transmission during FIFO fill");
      expect_field(ral.I3C_EC.TTI.IBI_QUEUE_DEPTH.IBI_QUEUE_DEPTH, 0,
                   "check initial IBI queue depth");
      expect_field(ral.I3C_EC.TTI.QUEUE_STATUS.IBI_QUEUE_EMPTY, 1,
                   "check initial IBI queue empty");

      vseq_ctx.cfg.ibi_expected_ack = 1'b1;
      vseq_ctx.cfg.ibi_expected_terminal_status = IBI_STATUS_SUCCESS;
      host_seq = i3c_host_respond_ibi_burst_seq::type_id::create(
        "host_burst_seq");
      fill_ibi_fifo(ral, host_seq, 0, record_count);
      `uvm_info(
        "IBI_FIFO_PHASE",
        $sformatf("Initial fill reached %0d DWORDs using %0d records",
                  vseq_ctx.cfg.ibi_queue_size, record_count),
        UVM_LOW)

      expect_field(
        ral.I3C_EC.TTI.IBI_QUEUE_DEPTH.IBI_QUEUE_DEPTH,
        vseq_ctx.cfg.ibi_queue_size, "check full IBI FIFO depth");
      expect_field(ral.I3C_EC.TTI.QUEUE_STATUS.IBI_QUEUE_FULL, 1,
                   "check IBI FIFO full flag");
      expect_field(ral.I3C_EC.TTI.QUEUE_STATUS.IBI_QUEUE_EMPTY, 0,
                   "check full IBI FIFO is not empty");

      // Unlike IBI_QUEUE_SIZE, target IBI_THLD is a direct free-entry count.
      // Use a middle value so both sides of the comparator are observable.
      threshold_entries = vseq_ctx.cfg.ibi_queue_size / 2;
      if (threshold_entries == 0)
        threshold_entries = 1;
      if (threshold_entries > 8'hff)
        threshold_entries = 8'hff;
      write_field(ral.I3C_EC.TTI.QUEUE_THLD_CTRL.IBI_THLD,
                   threshold_entries,
                   "set direct IBI free-space threshold to mid capacity");
      expect_field(ral.I3C_EC.TTI.QUEUE_THLD_CTRL.IBI_THLD,
                   threshold_entries,
                   "check programmed direct IBI threshold");
      expect_field(
        ral.I3C_EC.TTI.IBI_QUEUE_DEPTH.IBI_QUEUE_DEPTH,
        vseq_ctx.cfg.ibi_queue_size,
        "sample full FIFO below the programmed free-entry threshold");
      clear_w1c_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 1,
                      "clear stale IBI_DONE before FIFO drain");
      clear_w1c_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_THLD_STAT, 1,
                      "clear stale IBI threshold status while FIFO is full");
      expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 0,
                   "check initial FIFO drain IBI_DONE");
      expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_THLD_STAT, 0,
                   "check threshold inactive while FIFO is full");
      write_field(ral.I3C_EC.TTI.INTERRUPT_ENABLE.IBI_DONE_EN, 1,
                  "enable IBI_DONE interrupt");
      write_field(ral.I3C_EC.TTI.INTERRUPT_ENABLE.IBI_THLD_STAT_EN, 1,
                   "enable IBI threshold interrupt");
      wait_irq(1'b0, "check no enabled FIFO interrupt before drain");

      run_host_drain(ral, host_seq, record_count, completion_before,
                     mismatch_before, 1'b1, threshold_entries,
                     threshold_seen);
      `uvm_info(
        "IBI_FIFO_PHASE",
        $sformatf("Initial drain completed with threshold=%0d entries",
                  threshold_entries),
        UVM_LOW)

      expect_field(ral.I3C_EC.TTI.IBI_QUEUE_DEPTH.IBI_QUEUE_DEPTH, 0,
                   "check drained IBI queue depth");
      expect_field(ral.I3C_EC.TTI.QUEUE_STATUS.IBI_QUEUE_EMPTY, 1,
                   "check drained IBI queue empty flag");
      expect_field(ral.I3C_EC.TTI.QUEUE_STATUS.IBI_QUEUE_FULL, 0,
                   "check drained IBI queue full flag");
      expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.PENDING_IBI, 0,
                   "check no pending IBI after FIFO drain");
      wait_field_value(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_THLD_STAT, 1,
                       "wait for empty-FIFO threshold status");
      if (vseq_ctx.cfg.vif.i3c_irq !== 1'b1)
        `uvm_fatal("IBI_THLD_IRQ",
                   "Enabled IBI_THLD_STAT did not assert i3c_irq")

      write_field(ral.I3C_EC.TTI.INTERRUPT_ENABLE.IBI_THLD_STAT_EN, 0,
                   "disable IBI threshold interrupt after observation");
      clear_w1c_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_THLD_STAT, 1,
                      "clear observed IBI threshold status");
      expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_THLD_STAT, 0,
                   "check observed IBI threshold status clears");
      wait_irq(1'b0, "check IRQ clears after threshold status W1C");
      wait_bus_idle("check bus after FIFO/IRQ drain");

      // Refill and drain the same physical FIFO without reset. This forces
      // read/write pointers through another capacity and checks wrap reuse.
      write_field(ral.I3C_EC.TTI.CONTROL.IBI_EN, 0,
                  "hold IBI transmission during wrap refill");
      refill_host_seq = i3c_host_respond_ibi_burst_seq::type_id::create(
        "refill_host_burst_seq");
      fill_ibi_fifo(ral, refill_host_seq, record_count,
                    refill_record_count);
      `uvm_info(
        "IBI_FIFO_PHASE",
        $sformatf("Wrap refill reached %0d DWORDs using %0d records",
                  vseq_ctx.cfg.ibi_queue_size, refill_record_count),
        UVM_LOW)
      expect_field(
        ral.I3C_EC.TTI.IBI_QUEUE_DEPTH.IBI_QUEUE_DEPTH,
        vseq_ctx.cfg.ibi_queue_size, "check wrap-refilled IBI FIFO depth");
      expect_field(ral.I3C_EC.TTI.QUEUE_STATUS.IBI_QUEUE_FULL, 1,
                   "check wrap-refilled IBI FIFO full flag");
      clear_w1c_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 1,
                      "clear stale IBI_DONE before wrap drain");
      clear_w1c_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_THLD_STAT, 1,
                      "clear disabled threshold status before wrap drain");

      completion_before = vseq_ctx.cfg.ibi_sb_completion_count;
      run_host_drain(ral, refill_host_seq, refill_record_count,
                     completion_before, mismatch_before, 1'b0,
                     threshold_entries, refill_threshold_seen);
      `uvm_info("IBI_FIFO_PHASE", "Wrap drain completed", UVM_LOW)
      expect_field(ral.I3C_EC.TTI.IBI_QUEUE_DEPTH.IBI_QUEUE_DEPTH, 0,
                   "check wrap-drained IBI queue depth");
      expect_field(ral.I3C_EC.TTI.QUEUE_STATUS.IBI_QUEUE_EMPTY, 1,
                   "check wrap-drained IBI queue empty flag");
      expect_field(ral.I3C_EC.TTI.QUEUE_STATUS.IBI_QUEUE_FULL, 0,
                   "check wrap-drained IBI queue full flag");
      expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.PENDING_IBI, 0,
                   "check no pending IBI after wrap drain");
      clear_w1c_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_THLD_STAT, 1,
                      "clear disabled threshold status after wrap drain");
      wait_irq(1'b0, "check final IRQ after wrap drain");
      wait_bus_idle("check bus after wrap refill/drain");

      total_record_count = record_count + refill_record_count;
      attempt_samples = vseq_ctx.cfg.ibi_cov_attempt_samples -
                         attempt_samples_before;
      completion_samples = vseq_ctx.cfg.ibi_cov_completion_samples -
                           completion_samples_before;
      queue_irq_samples = vseq_ctx.cfg.ibi_cov_queue_irq_samples -
                          queue_irq_samples_before;
      threshold_below_samples =
        vseq_ctx.cfg.ibi_cov_threshold_below_samples -
        threshold_below_samples_before;
      threshold_reached_samples =
        vseq_ctx.cfg.ibi_cov_threshold_reached_samples -
        threshold_reached_samples_before;
      if ((attempt_samples < total_record_count) ||
          (completion_samples < total_record_count) ||
          (queue_irq_samples < total_record_count) ||
          (threshold_below_samples == 0) ||
          (threshold_reached_samples == 0)) begin
        if (vseq_ctx.cfg.require_ibi_coverage_samples)
          `uvm_fatal(
            "IBI_COVERAGE_WIRING",
            $sformatf("FIFO/IRQ coverage incomplete: records=%0d attempt=%0d completion=%0d queue_irq=%0d threshold_below=%0d threshold_reached=%0d",
                      total_record_count, attempt_samples, completion_samples,
                      queue_irq_samples, threshold_below_samples,
                      threshold_reached_samples))
        else
          `uvm_warning(
            "IBI_COVERAGE_WIRING",
            $sformatf("FIFO/IRQ checks passed with incomplete coverage: records=%0d attempt=%0d completion=%0d queue_irq=%0d threshold_below=%0d threshold_reached=%0d",
                      total_record_count, attempt_samples, completion_samples,
                      queue_irq_samples, threshold_below_samples,
                      threshold_reached_samples))
      end

      `uvm_info(
        "IBI_FIFO_IRQ_PASS",
        $sformatf("Checked %0d-entry threshold crossing and two %0d-DWORD FIFO fill/drain rounds (%0d ordered records) with pointer reuse",
                  threshold_entries, vseq_ctx.cfg.ibi_queue_size,
                  total_record_count),
        UVM_LOW)
    end
`else
    `uvm_fatal("IBI_RAL_BUILD",
               "i3c_ibi_target_tx_fifo_irq_test requires I3C_DV_NATIVE_RAL")
`endif
  endtask
endclass : i3c_ibi_target_tx_fifo_irq_vseq

`endif // I3C_IBI_TARGET_TX_FIFO_IRQ_VSEQ_SV
