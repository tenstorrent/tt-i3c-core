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
// File        : smc_i3c_ibi_target_tx_retry_arbitration_vseq.sv
// Description : Target IBI retry and repeated-arbitration virtual sequence.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-04
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_TARGET_TX_RETRY_ARBITRATION_VSEQ_SV
`define SMC_I3C_IBI_TARGET_TX_RETRY_ARBITRATION_VSEQ_SV

class smc_i3c_ibi_target_tx_retry_arbitration_vseq extends smc_i3c_ibi_base_vseq;
  `uvm_object_utils(smc_i3c_ibi_target_tx_retry_arbitration_vseq)

  function new(string name = "smc_i3c_ibi_target_tx_retry_arbitration_vseq");
    super.new(name);
  endfunction

  virtual task body();
    super.body();

    if (!vseq_ctx.cfg.has_rtl)
      `uvm_fatal("IBI_RETRY_MODE",
                 "IBI retry/arbitration test requires DUT_MODE=rtl")
    if (vseq_ctx.cfg.ibi_dut_role != SMC_I3C_IBI_DUT_TARGET)
      `uvm_fatal("IBI_RETRY_ROLE",
                 "IBI retry/arbitration test requires DUT-target role")
    if (!vseq_ctx.cfg.ibi_retry_tracking)
      `uvm_fatal("IBI_RETRY_TRACKING",
                 "Retry-aware observer tracking is not enabled")
    if ((vseq_ctx.cfg.ibi_retry_count == 0) ||
        (vseq_ctx.cfg.ibi_retry_count >= 7))
      `uvm_fatal("IBI_RETRY_COUNT",
                 $sformatf("Finite retry test requires IBI_RETRY_COUNT in [1:6], got %0d",
                           vseq_ctx.cfg.ibi_retry_count))

`ifndef SMC_USE_I3C_RTL
    `uvm_fatal("IBI_RETRY_RTL_BUILD",
               "IBI retry/arbitration test requires SMC_USE_I3C_RTL")
`elsif SMC_USE_I3C_RAL
    begin
      smc_i3c_ral_model ral;
      smc_i3c_host_respond_ibi_burst_seq host_seq;
      uvm_event host_armed_event;
      uvm_event host_detected_event;
      uvm_reg_data_t descriptor;
      uvm_reg_data_t payload_word;
      uvm_reg_data_t status;
      uvm_reg_data_t field_value;
      byte unsigned payload_bytes[$];
      int unsigned payload_len;
      int unsigned payload_words;
      int unsigned expected_attempts;
      int unsigned completion_before;
      int unsigned mismatch_before;
      int unsigned attempt_cov_before;
      int unsigned completion_cov_before;
      bit transaction_done;
      bit host_done;
      bit status_done;
      bit exhaust_retries;
      string pending_ibi_access;
      string pending_interrupt_access;

      if (vseq_ctx.i3c_sqr == null)
        `uvm_fatal("IBI_RETRY_SQR", "I3C host sequencer is not available")
      if (!vseq_ctx.cfg.has_ibi_scoreboard)
        `uvm_fatal("IBI_RETRY_SCOREBOARD",
                   "Retry/arbitration test requires the Target IBI scoreboard")

      payload_len = 0;
      void'($value$plusargs("IBI_RETRY_PAYLOAD_LEN=%0d", payload_len));
      if (payload_len > 8'hff)
        `uvm_fatal("IBI_RETRY_PAYLOAD",
                   "IBI_RETRY_PAYLOAD_LEN must be in [0:255]")

      ral = get_i3c_ral_model();
      exhaust_retries = vseq_ctx.cfg.ibi_retry_exhaustion;
      expected_attempts = vseq_ctx.cfg.ibi_retry_count + 1;
      completion_before = vseq_ctx.cfg.ibi_sb_completion_count;
      mismatch_before = vseq_ctx.cfg.ibi_sb_mismatch_count;
      attempt_cov_before = vseq_ctx.cfg.ibi_cov_attempt_samples;
      completion_cov_before = vseq_ctx.cfg.ibi_cov_completion_samples;

      vseq_ctx.cfg.ibi_expected_ack = !exhaust_retries;
      vseq_ctx.cfg.ibi_expected_terminal_status = exhaust_retries ?
        IBI_STATUS_FAILURE_RETRY : IBI_STATUS_SUCCESS;
      vseq_ctx.cfg.ibi_requester_count = 1;
      vseq_ctx.cfg.ibi_arb_outcome = 2'd0;
      vseq_ctx.cfg.ibi_bus_state = 2'd0;

      initialize_target_ibi(ral);
      write_field(ral.I3C_EC.TTI.INTERRUPT_ENABLE.IBI_DONE_EN, 1,
                  "enable retry IBI_DONE interrupt");
      clear_w1c_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 1,
                      "clear stale retry IBI_DONE");
      wait_irq(1'b0, "verify initial retry IRQ low");

      host_seq = smc_i3c_host_respond_ibi_burst_seq::type_id::create(
        "retry_host_seq");
      for (int unsigned attempt = 0;
           attempt < (exhaust_retries ? expected_attempts :
                      vseq_ctx.cfg.ibi_retry_count); attempt++) begin
        // A NACK ends this bus attempt without sampling MDB data. The DUT
        // retains the descriptor and arbitrates again when the bus is free.
        host_seq.rx_byte_count_q.push_back(0);
        host_seq.ibi_ack_q.push_back(1'b0);
      end
      if (!exhaust_retries) begin
        host_seq.rx_byte_count_q.push_back(payload_len + 1);
        host_seq.ibi_ack_q.push_back(1'b1);
      end

      payload_bytes.delete();
      for (int unsigned index = 0; index < payload_len; index++)
        payload_bytes.push_back(8'h70 + index[7:0]);
      descriptor = (uvm_reg_data_t'(vseq_ctx.cfg.ibi_basic_mdb) << 24) |
                   uvm_reg_data_t'(payload_len[7:0]);
      payload_words = (payload_len + 3) / 4;
      host_armed_event = uvm_event_pool::get_global(
        SMC_I3C_HOST_IBI_ARMED_EVENT);
      host_detected_event = uvm_event_pool::get_global(
        SMC_I3C_HOST_IBI_DETECTED_EVENT);
      host_armed_event.reset();
      host_detected_event.reset();
      transaction_done = 1'b0;
      host_done = 1'b0;
      status_done = 1'b0;

      fork : retry_timeout_guard
        begin
          fork
            begin
              host_seq.start(vseq_ctx.i3c_sqr);
              host_done = 1'b1;
            end
            begin
              host_armed_event.wait_on();
              // Consume the per-request ready indication. The Host driver
              // triggers this event for every burst entry, so leaving it set
              // would let a later retry reuse the first attempt's readiness.
              host_armed_event.reset();
              write_register(ral.I3C_EC.TTI.IBI_PORT, descriptor,
                             $sformatf("queue retry MDB+%0d payload descriptor",
                                       payload_len));
              for (int unsigned word_index = 0;
                   word_index < payload_words; word_index++) begin
                payload_word = '0;
                for (int unsigned lane = 0; lane < 4; lane++) begin
                  int unsigned flat_index;
                  flat_index = (word_index * 4) + lane;
                  if (flat_index < payload_len)
                    payload_word[8*lane +: 8] = payload_bytes[flat_index];
                end
                write_register(
                  ral.I3C_EC.TTI.IBI_PORT, payload_word,
                  $sformatf("queue retry payload word %0d", word_index));
              end
            end
            begin
              for (int unsigned attempt = 0;
                   attempt < expected_attempts; attempt++) begin
                host_detected_event.wait_on();
                host_detected_event.reset();

                if (attempt < vseq_ctx.cfg.ibi_retry_count)
                  write_field(
                    ral.I3C_EC.TTI.CONTROL.IBI_EN, 0,
                    $sformatf("pause automatic retry after attempt %0d",
                              attempt));

                wait_field_value(
                  ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 1,
                  $sformatf("wait for retry attempt %0d IBI_DONE", attempt));
                if (vseq_ctx.cfg.vif.i3c_irq !== 1'b1)
                  `uvm_fatal("IBI_RETRY_IRQ",
                             $sformatf("Attempt %0d set IBI_DONE without IRQ",
                                       attempt))

                read_field(
                  ral.I3C_EC.TTI.STATUS.LAST_IBI_STATUS, status,
                  $sformatf("capture retry attempt %0d status", attempt));
                if (attempt < vseq_ctx.cfg.ibi_retry_count) begin
                  if (status != uvm_reg_data_t'(IBI_STATUS_FAILURE_NACK))
                    `uvm_fatal(
                      "IBI_RETRY_STATUS",
                      $sformatf("Attempt %0d expected FAILURE_NACK, got 0x%0h",
                                attempt, status))
                  wait_irq(1'b0,
                           $sformatf("wait for attempt %0d IRQ clear",
                                     attempt));
                  wait_bus_idle(
                    $sformatf("wait for idle after NACK attempt %0d",
                              attempt));
                  // Bus high/high only proves that STOP is visible on the
                  // wires. The vendored Host VIP keeps the current request
                  // active throughout tHoldStop and cannot observe another
                  // Target START until it has accepted the next burst item.
                  // Keep IBI_EN low until that next Host request is armed;
                  // otherwise the DUT can legally retry before the Host is
                  // listening and both sides deadlock on the missed START.
                  if (attempt < (expected_attempts - 1)) begin
                    host_armed_event.wait_on();
                    host_armed_event.reset();
                    write_field(
                      ral.I3C_EC.TTI.CONTROL.IBI_EN, 1,
                      $sformatf("release automatic retry attempt %0d",
                                attempt + 1));
                  end
                end else begin
                  if (status != uvm_reg_data_t'(
                        exhaust_retries ? IBI_STATUS_FAILURE_RETRY :
                                          IBI_STATUS_SUCCESS))
                    `uvm_fatal(
                      "IBI_RETRY_STATUS",
                      $sformatf("Terminal attempt expected %s, got 0x%0h",
                                exhaust_retries ? "FAILURE_RETRY" :
                                                  "SUCCESS", status))
                  if (exhaust_retries)
                    clear_w1c_field(
                      ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 1,
                      "clear terminal retry-exhaustion IBI_DONE");
                  wait_irq(1'b0, "wait for terminal retry IRQ clear");
                end
              end
              status_done = 1'b1;
            end
          join
          transaction_done = 1'b1;
        end
        begin
          repeat (vseq_ctx.cfg.ibi_timeout_cycles *
                  (vseq_ctx.cfg.ibi_retry_count + 2))
            @(posedge vseq_ctx.cfg.vif.clk);
          if (!transaction_done)
            `uvm_fatal("IBI_RETRY_TIMEOUT",
                       "Timed out during bounded IBI retry sequence")
        end
      join_any
      disable retry_timeout_guard;

      if (!transaction_done || !host_done || !status_done)
        `uvm_fatal("IBI_RETRY_INCOMPLETE",
                   $sformatf("Retry sequence incomplete: transaction=%0b host=%0b status=%0b",
                             transaction_done, host_done, status_done))
      if (host_seq.response_count != expected_attempts)
        `uvm_fatal("IBI_RETRY_ATTEMPTS",
                   $sformatf("Expected %0d bus attempts, observed %0d",
                             expected_attempts, host_seq.response_count))
      foreach (host_seq.response_addr_q[index]) begin
        if (!host_seq.response_ibi_q[index] ||
            (host_seq.response_addr_q[index] !=
             vseq_ctx.cfg.ibi_target_addr))
          `uvm_fatal(
            "IBI_RETRY_WINNER",
            $sformatf("Attempt %0d did not resolve to the sole DUT Target 0x%02h",
                      index, vseq_ctx.cfg.ibi_target_addr))
      end

      wait_scoreboard_completion(completion_before + 1,
                                 "wait for terminal retry scoreboard result");
      if (vseq_ctx.cfg.ibi_sb_mismatch_count != mismatch_before)
        `uvm_fatal("IBI_RETRY_SCOREBOARD",
                   $sformatf("Retry sequence added %0d scoreboard mismatch(es)",
                             vseq_ctx.cfg.ibi_sb_mismatch_count -
                             mismatch_before))
      if (vseq_ctx.cfg.ibi_observed_retry_count !=
          vseq_ctx.cfg.ibi_retry_count)
        `uvm_fatal("IBI_RETRY_ACCOUNTING",
                   $sformatf("Configured retries=%0d observed retryable results=%0d",
                             vseq_ctx.cfg.ibi_retry_count,
                             vseq_ctx.cfg.ibi_observed_retry_count))
      if (vseq_ctx.cfg.ibi_observed_attempt_count != expected_attempts)
        `uvm_fatal("IBI_RETRY_ACCOUNTING",
                   $sformatf("Expected attempts=%0d observer attempts=%0d",
                             expected_attempts,
                             vseq_ctx.cfg.ibi_observed_attempt_count))
      if (((vseq_ctx.cfg.ibi_cov_attempt_samples - attempt_cov_before) !=
           expected_attempts) ||
          ((vseq_ctx.cfg.ibi_cov_completion_samples -
            completion_cov_before) !=
           expected_attempts))
        `uvm_fatal(
          "IBI_RETRY_COVERAGE",
          $sformatf("Expected %0d attempt/completion samples, got %0d/%0d",
                    expected_attempts,
                    vseq_ctx.cfg.ibi_cov_attempt_samples - attempt_cov_before,
                    vseq_ctx.cfg.ibi_cov_completion_samples -
                      completion_cov_before))

      if (exhaust_retries) begin
        // FAILURE_RETRY consumes the descriptor: the FIFO is empty even though
        // the independent PENDING_IBI status source remains asserted as a
        // terminal indication. Prove both facts before cleanup.
        expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.PENDING_IBI, 1,
                     "check retry-exhaustion PENDING_IBI status");
        expect_field(ral.I3C_EC.TTI.IBI_QUEUE_DEPTH.IBI_QUEUE_DEPTH, 0,
                     "check consumed retry-exhaustion descriptor");
        expect_field(ral.I3C_EC.TTI.QUEUE_STATUS.IBI_QUEUE_EMPTY, 1,
                     "check retry-exhaustion queue empty");

        // Reset the exhausted attempt counter, then handle PENDING_IBI
        // according to the generated RAL access policy. A RO implementation
        // is terminal diagnostic state, not a completion condition to poll:
        // waiting for it to clear only extends the finished transaction until
        // unrelated bounded-frame assertions time out.
        write_action_field(ral.I3C_EC.TTI.RESET_CONTROL.IBI_RETRY_CTR_RST, 1,
                           "reset exhausted IBI retry counter");
        pending_ibi_access =
          ral.I3C_EC.TTI.INTERRUPT_STATUS.PENDING_IBI.get_access(
            ral.default_map);
        case (pending_ibi_access)
          "W1C": clear_w1c_field(
            ral.I3C_EC.TTI.INTERRUPT_STATUS.PENDING_IBI, 1,
            "acknowledge retry-exhaustion PENDING_IBI");
          "RO": expect_field(
            ral.I3C_EC.TTI.INTERRUPT_STATUS.PENDING_IBI, 1,
            "confirm terminal retry-exhaustion PENDING_IBI");
          default:
            `uvm_fatal("IBI_RETRY_PENDING_ACCESS",
                       $sformatf("Unsupported PENDING_IBI access policy %s",
                                 pending_ibi_access))
        endcase
        pending_interrupt_access =
          ral.I3C_EC.TTI.INTERRUPT_STATUS.PENDING_INTERRUPT.get_access(
            ral.default_map);
        case (pending_interrupt_access)
          "W1C": clear_w1c_field(
            ral.I3C_EC.TTI.INTERRUPT_STATUS.PENDING_INTERRUPT, 1,
            "acknowledge retry-exhaustion PENDING_INTERRUPT");
          // Although the generated field policy is RW, the active hardware
          // PENDING_IBI source dominates software writes in this terminal
          // state. Confirm the aggregate remains asserted instead of claiming
          // that a write of zero can clear a still-active source.
          "RW": expect_field(
            ral.I3C_EC.TTI.INTERRUPT_STATUS.PENDING_INTERRUPT, 1,
            "confirm hardware-held retry-exhaustion PENDING_INTERRUPT");
          "RO": expect_field(
            ral.I3C_EC.TTI.INTERRUPT_STATUS.PENDING_INTERRUPT, 1,
            "confirm terminal retry-exhaustion PENDING_INTERRUPT");
          default:
            `uvm_fatal(
              "IBI_RETRY_PENDING_ACCESS",
              $sformatf("Unsupported PENDING_INTERRUPT access policy %s",
                        pending_interrupt_access))
        endcase
        clear_target_ibi_done_irq(ral, "finish retry-exhaustion cleanup");
      end

      if (!exhaust_retries) begin
        expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.PENDING_IBI, 0,
                     "check final successful retry PENDING_IBI");
        expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.PENDING_INTERRUPT, 0,
                     "check final successful retry PENDING_INTERRUPT");
      end
      read_field(ral.I3C_EC.TTI.IBI_QUEUE_DEPTH.IBI_QUEUE_DEPTH,
                 field_value, "check final retry queue depth");
      if (field_value != 0)
        `uvm_fatal("IBI_RETRY_QUEUE",
                   $sformatf("Terminal retry cleanup left queue depth=%0d",
                             field_value))
      expect_field(ral.I3C_EC.TTI.QUEUE_STATUS.IBI_QUEUE_EMPTY, 1,
                   "check final retry queue empty");
      wait_bus_idle("check bus idle after terminal retry result");

      `uvm_info(
        "IBI_RETRY_PASS",
        $sformatf("DUT Target 0x%02h tracked one MDB+%0d payload descriptor across %0d NACK retry/re-arbitrations and completed with %s",
                  vseq_ctx.cfg.ibi_target_addr,
                  payload_len,
                  exhaust_retries ? expected_attempts :
                    vseq_ctx.cfg.ibi_retry_count,
                  exhaust_retries ? "terminal FAILURE_RETRY" :
                    "one terminal ACK"),
        UVM_LOW)
    end
`else
    `uvm_fatal("IBI_RETRY_RAL_BUILD",
               "IBI retry/arbitration test requires SMC_USE_I3C_RAL")
`endif
  endtask
endclass : smc_i3c_ibi_target_tx_retry_arbitration_vseq

`endif // SMC_I3C_IBI_TARGET_TX_RETRY_ARBITRATION_VSEQ_SV
