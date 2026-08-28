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
// File        : smc_i3c_ibi_random_base_vseq.sv
// Description : Shared executor for constrained-random Target IBI scenarios.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-07
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_RANDOM_BASE_VSEQ_SV
`define SMC_I3C_IBI_RANDOM_BASE_VSEQ_SV

class smc_i3c_ibi_random_base_vseq extends smc_i3c_ibi_base_vseq;
  `uvm_object_utils(smc_i3c_ibi_random_base_vseq)

  function new(string name = "smc_i3c_ibi_random_base_vseq");
    super.new(name);
  endfunction

  protected virtual function int unsigned default_item_count();
    return 8;
  endfunction

  protected virtual function bit stress_profile();
    return 1'b0;
  endfunction

  protected virtual function bit mixed_response_profile();
    return 1'b0;
  endfunction

`ifdef SMC_USE_I3C_RTL
`ifdef SMC_USE_I3C_RAL
  protected task write_random_descriptor(
      input smc_i3c_ral_model ral,
      input smc_i3c_ibi_random_item item,
      input string phase_name);
    uvm_reg_data_t descriptor;
    uvm_reg_data_t payload_word;
    int unsigned payload_words;

    descriptor = (uvm_reg_data_t'(item.mdb) << 24) |
                 uvm_reg_data_t'(item.payload_len[7:0]);
    write_register(ral.I3C_EC.TTI.IBI_PORT, descriptor,
                   $sformatf("queue %s descriptor MDB=0x%02h payload=%0d",
                             phase_name, item.mdb, item.payload_len));

    payload_words = (item.payload_len + 3) / 4;
    for (int unsigned word_index = 0; word_index < payload_words;
         word_index++) begin
      payload_word = '0;
      for (int unsigned lane = 0; lane < 4; lane++) begin
        int unsigned flat_index;
        flat_index = (word_index * 4) + lane;
        if (flat_index < item.payload_len)
          payload_word[8*lane +: 8] =
            item.mdb ^ byte'(flat_index[7:0]) ^ 8'h5a;
      end
      write_register(ral.I3C_EC.TTI.IBI_PORT, payload_word,
                     $sformatf("queue %s payload word %0d",
                               phase_name, word_index));
    end
  endtask

  protected task wait_queue_reset_clear(input smc_i3c_ral_model ral,
                                        input string phase_name);
    uvm_reg_data_t reset_value;

    for (int unsigned poll = 0;
         poll < vseq_ctx.cfg.ibi_timeout_cycles; poll++) begin
      read_field(ral.I3C_EC.TTI.RESET_CONTROL.IBI_QUEUE_RST, reset_value,
                 $sformatf("wait for %s queue reset self-clear", phase_name));
      if (reset_value == 0)
        return;
      @(posedge vseq_ctx.cfg.vif.clk);
    end
    `uvm_fatal("IBI_RANDOM_QUEUE_RESET",
               $sformatf("%s queue reset did not self-clear", phase_name))
  endtask

  protected task run_direct_item(input smc_i3c_ral_model ral,
                                 input smc_i3c_ibi_random_item item,
                                 input string phase_name,
                                 input bit post_recovery_check = 1'b0);
    smc_i3c_host_respond_ibi_seq host_seq;
    uvm_event host_armed_event;
    uvm_event host_detected_event;
    uvm_reg_data_t status_value;
    ibi_terminal_status_e expected_status;
    bit expected_ack;
    bit transaction_done;
    bit status_captured;
    int unsigned completion_before;
    int unsigned mismatch_before;

    expected_ack = (item.response_mode == IBI_RANDOM_ACK);
    expected_status = expected_ack ? IBI_STATUS_SUCCESS :
                                     IBI_STATUS_FAILURE_NACK;
    completion_before = vseq_ctx.cfg.ibi_sb_completion_count;
    mismatch_before = vseq_ctx.cfg.ibi_sb_mismatch_count;
    vseq_ctx.cfg.ibi_retry_tracking = 1'b0;
    vseq_ctx.cfg.ibi_retry_count = 0;
    vseq_ctx.cfg.ibi_expected_ack = expected_ack;
    vseq_ctx.cfg.ibi_expected_terminal_status = expected_status;
    write_field(ral.I3C_EC.TTI.CONTROL.IBI_RETRY_NUM, 0,
                $sformatf("disable automatic retry for %s", phase_name));

    host_seq = smc_i3c_host_respond_ibi_seq::type_id::create(
      $sformatf("%s_host_seq", phase_name));
    host_seq.ibi_ack = expected_ack;
    host_seq.rx_byte_count = expected_ack ? item.payload_len + 1 : 0;
    host_armed_event = uvm_event_pool::get_global(
      SMC_I3C_HOST_IBI_ARMED_EVENT);
    host_detected_event = uvm_event_pool::get_global(
      SMC_I3C_HOST_IBI_DETECTED_EVENT);
    host_armed_event.reset();
    host_detected_event.reset();
    transaction_done = 1'b0;
    status_captured = 1'b0;

    fork : random_direct_timeout_guard
      begin
        fork
          host_seq.start(vseq_ctx.i3c_sqr);
          begin
            host_armed_event.wait_on();
            write_random_descriptor(ral, item, phase_name);
          end
          begin
            if (!expected_ack) begin
              host_detected_event.wait_on();
              write_field(ral.I3C_EC.TTI.CONTROL.IBI_EN, 0,
                          $sformatf("pause Target retry during %s NACK",
                                    phase_name));
            end
          end
          begin
            wait_irq(1'b1, $sformatf("wait for %s IBI_DONE", phase_name));
            expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 1,
                         $sformatf("confirm %s IBI_DONE", phase_name));
            read_field(ral.I3C_EC.TTI.STATUS.LAST_IBI_STATUS, status_value,
                       $sformatf("capture %s terminal status", phase_name));
            status_captured = 1'b1;
            if (status_value != uvm_reg_data_t'(expected_status)) begin
              if (post_recovery_check) begin
                uvm_reg_data_t queue_depth;
                uvm_reg_data_t queue_empty;
                uvm_reg_data_t ibi_done;

                read_field(ral.I3C_EC.TTI.IBI_QUEUE_DEPTH.IBI_QUEUE_DEPTH,
                           queue_depth, "capture random recovery queue depth");
                read_field(ral.I3C_EC.TTI.QUEUE_STATUS.IBI_QUEUE_EMPTY,
                           queue_empty, "capture random recovery queue empty");
                read_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, ibi_done,
                           "capture random recovery IBI_DONE");
                `uvm_info("IBI_RECOVERY_DIAG",
                          $sformatf("phase=%s expected=%s actual=0x%0h queue_depth=%0h queue_empty=%0h IBI_DONE=%0h attempts=%0d completions=%0d",
                                    phase_name, expected_status.name(),
                                    status_value, queue_depth, queue_empty,
                                    ibi_done,
                                    vseq_ctx.cfg.ibi_cov_attempt_samples,
                                    vseq_ctx.cfg.ibi_sb_completion_count),
                          UVM_NONE)
                `uvm_fatal("IBI_RECOVERY_STATUS_MISMATCH",
                           $sformatf("%s did not recover to %s: terminal status remained 0x%0h",
                                     phase_name, expected_status.name(),
                                     status_value))
              end else begin
                `uvm_fatal("IBI_RANDOM_STATUS",
                           $sformatf("%s expected %s, actual=0x%0h",
                                     phase_name, expected_status.name(),
                                     status_value))
              end
            end
            if (!expected_ack) begin
              write_action_field(
                ral.I3C_EC.TTI.RESET_CONTROL.IBI_QUEUE_RST, 1,
                $sformatf("flush retained descriptor after %s NACK",
                          phase_name));
              wait_queue_reset_clear(ral, phase_name);
              rearm_target_ibi_after_queue_reset(
                ral, $sformatf("re-arm Target after %s NACK", phase_name));
            end
          end
        join
        transaction_done = 1'b1;
      end
      begin
        repeat (vseq_ctx.cfg.ibi_timeout_cycles)
          @(posedge vseq_ctx.cfg.vif.clk);
        if (!transaction_done)
          `uvm_fatal("IBI_RANDOM_TIMEOUT",
                     $sformatf("Timed out during %s", phase_name))
      end
    join_any
    disable random_direct_timeout_guard;

    if (!transaction_done || !host_seq.response_valid || !status_captured)
      `uvm_fatal("IBI_RANDOM_INCOMPLETE",
                 $sformatf("%s incomplete host=%0b status=%0b",
                           phase_name, host_seq.response_valid,
                           status_captured))
    clear_target_ibi_done_irq(
      ral, $sformatf("complete %s response handling", phase_name));
    wait_scoreboard_completion(completion_before + 1,
                               $sformatf("wait for %s scoreboard", phase_name));
    if (vseq_ctx.cfg.ibi_sb_mismatch_count != mismatch_before)
      `uvm_fatal("IBI_RANDOM_SCOREBOARD",
                 $sformatf("%s added %0d mismatch(es)", phase_name,
                           vseq_ctx.cfg.ibi_sb_mismatch_count -
                           mismatch_before))
    wait_bus_idle($sformatf("wait for idle after %s", phase_name));
  endtask

  protected task run_retry_item(input smc_i3c_ral_model ral,
                                input smc_i3c_ibi_random_item item,
                                input string phase_name);
    smc_i3c_host_respond_ibi_burst_seq host_seq;
    uvm_event host_armed_event;
    uvm_event host_detected_event;
    uvm_reg_data_t descriptor;
    uvm_reg_data_t status_value;
    int unsigned expected_attempts;
    int unsigned completion_before;
    int unsigned mismatch_before;
    int unsigned observed_retry_before;
    int unsigned observed_attempt_before;
    bit transaction_done;
    bit host_done;
    bit status_done;

    expected_attempts = item.nack_count_before_ack + 1;
    completion_before = vseq_ctx.cfg.ibi_sb_completion_count;
    mismatch_before = vseq_ctx.cfg.ibi_sb_mismatch_count;
    observed_retry_before = vseq_ctx.cfg.ibi_observed_retry_count;
    observed_attempt_before = vseq_ctx.cfg.ibi_observed_attempt_count;
    vseq_ctx.cfg.ibi_retry_tracking = 1'b1;
    vseq_ctx.cfg.ibi_retry_count = item.nack_count_before_ack;
    vseq_ctx.cfg.ibi_expected_ack = 1'b1;
    vseq_ctx.cfg.ibi_expected_terminal_status = IBI_STATUS_SUCCESS;
    write_field(ral.I3C_EC.TTI.CONTROL.IBI_RETRY_NUM,
                item.nack_count_before_ack,
                $sformatf("set %s retry budget", phase_name));

    host_seq = smc_i3c_host_respond_ibi_burst_seq::type_id::create(
      $sformatf("%s_host_seq", phase_name));
    for (int unsigned attempt = 0;
         attempt < item.nack_count_before_ack; attempt++) begin
      host_seq.rx_byte_count_q.push_back(0);
      host_seq.ibi_ack_q.push_back(1'b0);
    end
    host_seq.rx_byte_count_q.push_back(1);
    host_seq.ibi_ack_q.push_back(1'b1);

    descriptor = uvm_reg_data_t'(item.mdb) << 24;
    host_armed_event = uvm_event_pool::get_global(
      SMC_I3C_HOST_IBI_ARMED_EVENT);
    host_detected_event = uvm_event_pool::get_global(
      SMC_I3C_HOST_IBI_DETECTED_EVENT);
    host_armed_event.reset();
    host_detected_event.reset();
    transaction_done = 1'b0;
    host_done = 1'b0;
    status_done = 1'b0;

    fork : random_retry_timeout_guard
      begin
        fork
          begin
            host_seq.start(vseq_ctx.i3c_sqr);
            host_done = 1'b1;
          end
          begin
            host_armed_event.wait_on();
            host_armed_event.reset();
            write_register(ral.I3C_EC.TTI.IBI_PORT, descriptor,
                           $sformatf("queue %s retry descriptor MDB=0x%02h",
                                     phase_name, item.mdb));
          end
          begin
            for (int unsigned attempt = 0;
                 attempt < expected_attempts; attempt++) begin
              host_detected_event.wait_on();
              host_detected_event.reset();
              if (attempt < item.nack_count_before_ack)
                write_field(ral.I3C_EC.TTI.CONTROL.IBI_EN, 0,
                            $sformatf("pause %s after NACK %0d",
                                      phase_name, attempt));
              wait_field_value(
                ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 1,
                $sformatf("wait for %s attempt %0d IBI_DONE",
                          phase_name, attempt));
              read_field(ral.I3C_EC.TTI.STATUS.LAST_IBI_STATUS,
                         status_value,
                         $sformatf("capture %s attempt %0d status",
                                   phase_name, attempt));
              if (attempt < item.nack_count_before_ack) begin
                if (status_value !=
                    uvm_reg_data_t'(IBI_STATUS_FAILURE_NACK))
                  `uvm_fatal("IBI_RANDOM_RETRY_STATUS",
                             $sformatf("%s attempt %0d expected NACK, got 0x%0h",
                                       phase_name, attempt, status_value))
                clear_target_ibi_done_irq(
                  ral, $sformatf("complete %s NACK attempt %0d",
                                 phase_name, attempt));
                wait_bus_idle(
                  $sformatf("wait for %s idle after NACK", phase_name));
                host_armed_event.wait_on();
                host_armed_event.reset();
                write_field(ral.I3C_EC.TTI.CONTROL.IBI_EN, 1,
                            $sformatf("release %s retry %0d",
                                      phase_name, attempt + 1));
              end else begin
                if (status_value != uvm_reg_data_t'(IBI_STATUS_SUCCESS))
                  `uvm_fatal("IBI_RANDOM_RETRY_STATUS",
                             $sformatf("%s terminal attempt expected SUCCESS, got 0x%0h",
                                       phase_name, status_value))
                clear_target_ibi_done_irq(
                  ral, $sformatf("complete %s terminal attempt", phase_name));
              end
            end
            status_done = 1'b1;
          end
        join
        transaction_done = 1'b1;
      end
      begin
        repeat (vseq_ctx.cfg.ibi_timeout_cycles * (expected_attempts + 1))
          @(posedge vseq_ctx.cfg.vif.clk);
        if (!transaction_done)
          `uvm_fatal("IBI_RANDOM_RETRY_TIMEOUT",
                     $sformatf("Timed out during %s", phase_name))
      end
    join_any
    disable random_retry_timeout_guard;

    if (!transaction_done || !host_done || !status_done)
      `uvm_fatal("IBI_RANDOM_RETRY_INCOMPLETE",
                 $sformatf("%s incomplete transaction=%0b host=%0b status=%0b",
                           phase_name, transaction_done, host_done,
                           status_done))
    if (host_seq.response_count != expected_attempts)
      `uvm_fatal("IBI_RANDOM_RETRY_ATTEMPTS",
                 $sformatf("%s expected %0d responses, observed %0d",
                           phase_name, expected_attempts,
                           host_seq.response_count))
    wait_scoreboard_completion(completion_before + 1,
                               $sformatf("wait for %s terminal scoreboard",
                                         phase_name));
    if (vseq_ctx.cfg.ibi_sb_mismatch_count != mismatch_before)
      `uvm_fatal("IBI_RANDOM_RETRY_SCOREBOARD",
                 $sformatf("%s added %0d mismatch(es)", phase_name,
                           vseq_ctx.cfg.ibi_sb_mismatch_count -
                           mismatch_before))
    if ((vseq_ctx.cfg.ibi_observed_retry_count - observed_retry_before) !=
        item.nack_count_before_ack)
      `uvm_fatal("IBI_RANDOM_RETRY_ACCOUNTING",
                 $sformatf("%s planned NACKs=%0d observed=%0d",
                           phase_name, item.nack_count_before_ack,
                           vseq_ctx.cfg.ibi_observed_retry_count -
                           observed_retry_before))
    if ((vseq_ctx.cfg.ibi_observed_attempt_count - observed_attempt_before) !=
        expected_attempts)
      `uvm_fatal("IBI_RANDOM_RETRY_ACCOUNTING",
                 $sformatf("%s expected attempts=%0d observed=%0d",
                           phase_name, expected_attempts,
                           vseq_ctx.cfg.ibi_observed_attempt_count -
                           observed_attempt_before))

    vseq_ctx.cfg.ibi_retry_tracking = 1'b0;
    vseq_ctx.cfg.ibi_retry_count = 0;
    write_field(ral.I3C_EC.TTI.CONTROL.IBI_RETRY_NUM, 0,
                $sformatf("restore retry budget after %s", phase_name));
    wait_bus_idle($sformatf("wait for idle after %s", phase_name));
  endtask
`endif
`endif

  virtual task body();
    int unsigned item_count;
    int unsigned max_payload;

    super.body();
    if (!vseq_ctx.cfg.has_rtl)
      `uvm_fatal("IBI_RANDOM_MODE", "Random IBI test requires DUT_MODE=rtl")
    if (vseq_ctx.cfg.ibi_dut_role != SMC_I3C_IBI_DUT_TARGET)
      `uvm_fatal("IBI_RANDOM_ROLE",
                 "Target random IBI vseq requires DUT-target role")

`ifndef SMC_USE_I3C_RTL
    `uvm_fatal("IBI_RANDOM_RTL_BUILD",
               "Random IBI test requires SMC_USE_I3C_RTL")
`elsif SMC_USE_I3C_RAL
    begin
      smc_i3c_ral_model ral;
      smc_i3c_ibi_random_plan plan;
      int unsigned planned_attempts;
      int unsigned attempt_before;
      int unsigned completion_before;
      int unsigned queue_before;
      int unsigned mismatch_before;
      int unsigned attempt_delta;
      int unsigned completion_delta;
      int unsigned queue_delta;
      int unsigned must_hit_enable;
      bit seen_mdb_000;
      bit seen_mdb_001;
      bit seen_mdb_101;
      bit seen_mdb_other;
      bit seen_payload_none;
      bit seen_payload_one;
      bit seen_payload_medium;
      bit seen_payload_long;
      bit seen_ack;
      bit seen_nack;
      bit seen_retry_one;
      bit seen_retry_few;
      bit seen_retry_many;
      bit seen_gap_zero;
      bit seen_gap_nonzero;
      bit post_flush_check;

      item_count = default_item_count();
      max_payload = 16;
      must_hit_enable = 0;
      void'($value$plusargs("IBI_RANDOM_ITERS=%0d", item_count));
      void'($value$plusargs("IBI_RANDOM_MAX_PAYLOAD=%0d", max_payload));
      void'($value$plusargs("IBI_RANDOM_MUST_HIT=%0d", must_hit_enable));
      if (item_count == 0)
        `uvm_fatal("IBI_RANDOM_COUNT", "IBI_RANDOM_ITERS must be non-zero")
      if (max_payload > 8'hff)
        `uvm_fatal("IBI_RANDOM_PAYLOAD",
                   "IBI_RANDOM_MAX_PAYLOAD must be in [0:255]")
      if ((must_hit_enable != 0) && (max_payload < 9))
        `uvm_fatal("IBI_RANDOM_MUST_HIT_PAYLOAD",
                   "IBI_RANDOM_MUST_HIT requires IBI_RANDOM_MAX_PAYLOAD >= 9")
      if (vseq_ctx.i3c_sqr == null)
        `uvm_fatal("IBI_RANDOM_SQR", "I3C host sequencer is unavailable")
      if (!vseq_ctx.cfg.has_ibi_scoreboard)
        `uvm_fatal("IBI_RANDOM_SCOREBOARD",
                   "Target random test requires the IBI scoreboard")

      plan = smc_i3c_ibi_random_plan::type_id::create("plan");
      plan.build(item_count, max_payload, 1'b0, stress_profile(),
                 mixed_response_profile(), must_hit_enable != 0);
      plan.print_plan(stress_profile() ? "IBI_STRESS_PLAN" :
                                         "IBI_RANDOM_PLAN");

      foreach (plan.items[index]) begin
        case (plan.items[index].mdb_class)
          IBI_RANDOM_MDB_000:   seen_mdb_000 = 1'b1;
          IBI_RANDOM_MDB_001:   seen_mdb_001 = 1'b1;
          IBI_RANDOM_MDB_101:   seen_mdb_101 = 1'b1;
          IBI_RANDOM_MDB_OTHER: seen_mdb_other = 1'b1;
        endcase
        if (plan.items[index].payload_len == 0)
          seen_payload_none = 1'b1;
        else if (plan.items[index].payload_len == 1)
          seen_payload_one = 1'b1;
        else if (plan.items[index].payload_len <= 8)
          seen_payload_medium = 1'b1;
        else
          seen_payload_long = 1'b1;
        case (plan.items[index].response_mode)
          IBI_RANDOM_ACK: seen_ack = 1'b1;
          IBI_RANDOM_NACK_FLUSH: seen_nack = 1'b1;
          IBI_RANDOM_RETRY_ACK: begin
            if (plan.items[index].nack_count_before_ack == 1)
              seen_retry_one = 1'b1;
            else if (plan.items[index].nack_count_before_ack <= 3)
              seen_retry_few = 1'b1;
            else
              seen_retry_many = 1'b1;
          end
        endcase
        if (plan.items[index].inter_ibi_gap == 0)
          seen_gap_zero = 1'b1;
        else
          seen_gap_nonzero = 1'b1;
      end
      `uvm_info("IBI_RANDOM_BUCKETS",
                $sformatf({"mdb=%0b%0b%0b%0b payload=%0b%0b%0b%0b ",
                           "response=%0b%0b retry=%0b%0b%0b gap=%0b%0b"},
                          seen_mdb_000, seen_mdb_001, seen_mdb_101,
                          seen_mdb_other, seen_payload_none,
                          seen_payload_one, seen_payload_medium,
                          seen_payload_long, seen_ack, seen_nack,
                          seen_retry_one, seen_retry_few, seen_retry_many,
                          seen_gap_zero, seen_gap_nonzero), UVM_LOW)
      if ((must_hit_enable != 0) &&
          !(seen_mdb_000 && seen_mdb_001 && seen_mdb_101 &&
            seen_mdb_other && seen_payload_none && seen_payload_one &&
            seen_payload_medium && seen_payload_long && seen_ack &&
            seen_nack && seen_retry_one && seen_retry_few &&
            seen_retry_many && seen_gap_zero && seen_gap_nonzero))
        `uvm_fatal("IBI_RANDOM_MUST_HIT",
                   "Coverage-directed random plan missed a required bucket")

      ral = get_i3c_ral_model();
      initialize_target_ibi(ral);
      write_field(ral.I3C_EC.TTI.INTERRUPT_ENABLE.IBI_DONE_EN, 1,
                  "enable random IBI_DONE interrupt");
      clear_w1c_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 1,
                      "clear stale random IBI_DONE");
      wait_irq(1'b0, "verify initial random IRQ low");

      attempt_before = vseq_ctx.cfg.ibi_cov_attempt_samples;
      completion_before = vseq_ctx.cfg.ibi_cov_completion_samples;
      queue_before = vseq_ctx.cfg.ibi_cov_queue_irq_samples;
      mismatch_before = vseq_ctx.cfg.ibi_sb_mismatch_count;
      planned_attempts = 0;
      post_flush_check = 1'b0;

      foreach (plan.items[index]) begin
        repeat (plan.items[index].inter_ibi_gap)
          @(posedge vseq_ctx.cfg.vif.clk);
        if (plan.items[index].response_mode == IBI_RANDOM_RETRY_ACK) begin
          planned_attempts += plan.items[index].nack_count_before_ack + 1;
          run_retry_item(ral, plan.items[index],
                         $sformatf("RANDOM_%0d", index));
          post_flush_check = 1'b0;
        end else begin
          planned_attempts++;
          run_direct_item(ral, plan.items[index],
                          $sformatf("RANDOM_%0d", index),
                          post_flush_check &&
                          (plan.items[index].response_mode == IBI_RANDOM_ACK));
          post_flush_check =
            (plan.items[index].response_mode == IBI_RANDOM_NACK_FLUSH);
        end
      end

      attempt_delta = vseq_ctx.cfg.ibi_cov_attempt_samples - attempt_before;
      completion_delta = vseq_ctx.cfg.ibi_cov_completion_samples -
                         completion_before;
      queue_delta = vseq_ctx.cfg.ibi_cov_queue_irq_samples - queue_before;
      if ((attempt_delta < planned_attempts) ||
          (completion_delta < planned_attempts) ||
          (queue_delta < plan.items.size())) begin
        if (vseq_ctx.cfg.require_ibi_coverage_samples)
          `uvm_fatal("IBI_RANDOM_COVERAGE",
                     $sformatf("Coverage samples attempt=%0d completion=%0d queue=%0d expected>=%0d/%0d/%0d",
                               attempt_delta, completion_delta, queue_delta,
                               planned_attempts, planned_attempts,
                               plan.items.size()))
        else
          `uvm_warning("IBI_RANDOM_COVERAGE",
                       $sformatf("Coverage samples incomplete attempt=%0d completion=%0d queue=%0d expected>=%0d/%0d/%0d",
                                 attempt_delta, completion_delta, queue_delta,
                                 planned_attempts, planned_attempts,
                                 plan.items.size()))
      end
      if (vseq_ctx.cfg.ibi_sb_mismatch_count != mismatch_before)
        `uvm_fatal("IBI_RANDOM_SCOREBOARD",
                   $sformatf("Random plan added %0d scoreboard mismatch(es)",
                             vseq_ctx.cfg.ibi_sb_mismatch_count -
                             mismatch_before))

      `uvm_info(stress_profile() ? "IBI_STRESS_PASS" : "IBI_RANDOM_PASS",
                $sformatf("Completed items=%0d planned_attempts=%0d coverage=%0d/%0d/%0d",
                          plan.items.size(), planned_attempts, attempt_delta,
                          completion_delta, queue_delta),
                UVM_LOW)
    end
`else
    `uvm_fatal("IBI_RANDOM_RAL_BUILD",
               "Random IBI test requires SMC_USE_I3C_RAL")
`endif
  endtask
endclass : smc_i3c_ibi_random_base_vseq

`endif // SMC_I3C_IBI_RANDOM_BASE_VSEQ_SV
