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
// File        : smc_i3c_ibi_target_tx_ack_nack_vseq.sv
// Description : Virtual sequence for I3C IBI ACK and NACK responses.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-24
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_TARGET_TX_ACK_NACK_VSEQ_SV
`define SMC_I3C_IBI_TARGET_TX_ACK_NACK_VSEQ_SV

class smc_i3c_ibi_target_tx_ack_nack_vseq extends smc_i3c_ibi_base_vseq;
  `uvm_object_utils(smc_i3c_ibi_target_tx_ack_nack_vseq)

  function new(string name = "smc_i3c_ibi_target_tx_ack_nack_vseq");
    super.new(name);
  endfunction

`ifdef SMC_USE_I3C_RTL
`ifdef SMC_USE_I3C_RAL
  protected task run_mdb_only_ibi_response(
      input smc_i3c_ral_model ral,
      input bit host_ack,
      input ibi_terminal_status_e expected_status,
      input string phase_name,
      input bit post_recovery_check = 1'b0);
    smc_i3c_host_respond_ibi_seq host_seq;
    uvm_event host_armed_event;
    uvm_event host_detected_event;
    uvm_reg_data_t field_value;
    uvm_reg_data_t ibi_descriptor;
    bit transaction_done;
    bit status_captured;
    int unsigned completion_before;
    int unsigned mismatch_before;

    completion_before = vseq_ctx.cfg.ibi_sb_completion_count;
    mismatch_before = vseq_ctx.cfg.ibi_sb_mismatch_count;
    vseq_ctx.cfg.ibi_expected_ack = host_ack;
    vseq_ctx.cfg.ibi_expected_terminal_status = expected_status;

    host_seq = smc_i3c_host_respond_ibi_seq::type_id::create(
      $sformatf("%s_host_seq", phase_name));
    host_seq.ibi_ack = host_ack;
    ibi_descriptor = uvm_reg_data_t'(vseq_ctx.cfg.ibi_basic_mdb) << 24;
    host_armed_event = uvm_event_pool::get_global(
      SMC_I3C_HOST_IBI_ARMED_EVENT);
    host_detected_event = uvm_event_pool::get_global(
      SMC_I3C_HOST_IBI_DETECTED_EVENT);
    host_armed_event.reset();
    host_detected_event.reset();
    transaction_done = 1'b0;
    status_captured = 1'b0;

    fork : ibi_response_timeout_guard
      begin
        fork
          host_seq.start(vseq_ctx.i3c_sqr);
          begin
            host_armed_event.wait_on();
            write_register(ral.I3C_EC.TTI.IBI_PORT, ibi_descriptor,
                           $sformatf("queue %s MDB-only IBI descriptor",
                                      phase_name));
          end
          begin
            if (!host_ack) begin
              host_detected_event.wait_on();
              write_field(ral.I3C_EC.TTI.CONTROL.IBI_EN, 0,
                          "pause Target retry at observed NACK boundary");
            end
          end
          begin
            wait_irq(1'b1,
                     $sformatf("wait for %s IBI_DONE IRQ", phase_name));
            expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 1,
                         $sformatf("confirm %s IBI_DONE source", phase_name));
            // Read the terminal result at the first IRQ boundary. In the NACK
            // case the retained descriptor may otherwise enter retry and
            // overwrite FAILURE_NACK with FAILURE_RETRY.
            read_field(ral.I3C_EC.TTI.STATUS.LAST_IBI_STATUS, field_value,
                       $sformatf("capture first %s LAST_IBI_STATUS",
                                 phase_name));
            status_captured = 1'b1;
            if (field_value != uvm_reg_data_t'(expected_status)) begin
              if (post_recovery_check) begin
                uvm_reg_data_t ibi_enable;
                uvm_reg_data_t retry_count;
                uvm_reg_data_t queue_depth;
                uvm_reg_data_t queue_empty;
                uvm_reg_data_t ibi_done;

                read_field(ral.I3C_EC.TTI.CONTROL.IBI_EN, ibi_enable,
                           "capture post-recovery IBI enable");
                read_field(ral.I3C_EC.TTI.CONTROL.IBI_RETRY_NUM, retry_count,
                           "capture post-recovery retry count");
                read_field(ral.I3C_EC.TTI.IBI_QUEUE_DEPTH.IBI_QUEUE_DEPTH,
                           queue_depth, "capture post-recovery queue depth");
                read_field(ral.I3C_EC.TTI.QUEUE_STATUS.IBI_QUEUE_EMPTY,
                           queue_empty, "capture post-recovery queue empty");
                read_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, ibi_done,
                           "capture post-recovery IBI_DONE");
                `uvm_info("IBI_RECOVERY_DIAG",
                          $sformatf("phase=%s expected=%s actual=0x%0h IBI_EN=%0h IBI_RETRY_NUM=%0h queue_depth=%0h queue_empty=%0h IBI_DONE=%0h attempts=%0d completions=%0d",
                                    phase_name, expected_status.name(), field_value,
                                    ibi_enable, retry_count, queue_depth,
                                    queue_empty, ibi_done,
                                    vseq_ctx.cfg.ibi_cov_attempt_samples,
                                    vseq_ctx.cfg.ibi_sb_completion_count),
                          UVM_NONE)
                `uvm_fatal("IBI_RECOVERY_STATUS_MISMATCH",
                           $sformatf("%s did not recover to %s: terminal status remained 0x%0h",
                                     phase_name, expected_status.name(),
                                     field_value))
              end else begin
                `uvm_fatal("IBI_TERMINAL_STATUS",
                           $sformatf("%s expected first status=%s (0x%0h), actual=0x%0h",
                                     phase_name, expected_status.name(),
                                     expected_status, field_value))
              end
            end

            if (!host_ack) begin
              // Address NACK retains the descriptor. Remove it immediately
              // after observing FAILURE_NACK so this test does not turn into
              // a retry-exhaustion test.
              write_action_field(ral.I3C_EC.TTI.RESET_CONTROL.IBI_QUEUE_RST, 1,
                                 "flush descriptor after observed IBI NACK");
              for (int unsigned poll = 0;
                   poll < vseq_ctx.cfg.ibi_timeout_cycles; poll++) begin
                read_field(ral.I3C_EC.TTI.RESET_CONTROL.IBI_QUEUE_RST,
                           field_value,
                           "wait for IBI queue reset self-clear");
                if (field_value == 0)
                  break;
                if (poll == (vseq_ctx.cfg.ibi_timeout_cycles - 1))
                  `uvm_fatal("IBI_QUEUE_RESET_TIMEOUT",
                             "IBI queue reset did not self-clear after NACK")
              end
              rearm_target_ibi_after_queue_reset(
                ral, "re-arm Target after observed IBI NACK");
            end
          end
        join
        transaction_done = 1'b1;
      end
      begin
        repeat (vseq_ctx.cfg.ibi_timeout_cycles)
          @(posedge vseq_ctx.cfg.vif.clk);
        if (!transaction_done)
          `uvm_fatal("IBI_RESPONSE_TIMEOUT",
                     $sformatf("Timed out waiting for %s IBI completion",
                               phase_name))
      end
    join_any
    disable ibi_response_timeout_guard;

    if (!transaction_done || !host_seq.response_valid || !status_captured)
      `uvm_fatal("IBI_HOST_CHECK",
                 $sformatf("%s IBI did not complete all required observations: host=%0b status=%0b",
                           phase_name, host_seq.response_valid,
                           status_captured))

    clear_target_ibi_done_irq(
      ral, $sformatf("complete %s response handling", phase_name));
    wait_scoreboard_completion(completion_before + 1,
                               $sformatf("wait for %s scoreboard result",
                                         phase_name));
    if (vseq_ctx.cfg.ibi_sb_mismatch_count != mismatch_before)
      `uvm_fatal("IBI_SCOREBOARD_CHECK",
                 $sformatf("%s added %0d scoreboard mismatch(es)",
                           phase_name,
                           vseq_ctx.cfg.ibi_sb_mismatch_count - mismatch_before))

    expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.PENDING_IBI, 0,
                 $sformatf("check final %s PENDING_IBI", phase_name));
    expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.PENDING_INTERRUPT, 0,
                 $sformatf("check final %s PENDING_INTERRUPT", phase_name));
    read_field(ral.I3C_EC.TTI.IBI_QUEUE_DEPTH.IBI_QUEUE_DEPTH, field_value,
               $sformatf("observe final %s IBI queue depth", phase_name));
    read_field(ral.I3C_EC.TTI.QUEUE_STATUS.IBI_QUEUE_EMPTY, field_value,
               $sformatf("observe final %s IBI queue empty", phase_name));
    wait_bus_idle($sformatf("check bus after %s IBI", phase_name));
  endtask
`endif
`endif

  virtual task body();
    super.body();

    if (!vseq_ctx.cfg.has_rtl)
      `uvm_fatal("SMC_I3C_MODE",
                 "smc_i3c_ibi_target_tx_ack_nack_test requires DUT_MODE=rtl")
    if (vseq_ctx.cfg.ibi_dut_role != SMC_I3C_IBI_DUT_TARGET)
      `uvm_fatal("IBI_ACK_NACK_ROLE",
                 "smc_i3c_ibi_target_tx_ack_nack_test covers DUT-target transmit only")
`ifndef SMC_USE_I3C_RTL
    `uvm_fatal("IBI_VIP_BUILD", "I3C host VIP is available only in DUT_MODE=rtl")
`elsif SMC_USE_I3C_RAL
    begin
      smc_i3c_ral_model ral;
      uvm_reg_data_t field_value;
      int unsigned attempt_samples_before;
      int unsigned completion_samples_before;
      int unsigned queue_irq_samples_before;
      int unsigned attempt_samples;
      int unsigned completion_samples;
      int unsigned queue_irq_samples;

      if (vseq_ctx.i3c_sqr == null)
        `uvm_fatal("IBI_HOST_SQR", "I3C host sequencer is not available")
      if (!vseq_ctx.cfg.has_ibi_scoreboard)
        `uvm_fatal("IBI_SCOREBOARD_CFG",
                   "ACK/NACK test requires the IBI scoreboard")

      ral = get_i3c_ral_model();
      attempt_samples_before = vseq_ctx.cfg.ibi_cov_attempt_samples;
      completion_samples_before = vseq_ctx.cfg.ibi_cov_completion_samples;
      queue_irq_samples_before = vseq_ctx.cfg.ibi_cov_queue_irq_samples;

      initialize_target_ibi(ral);
      write_field(ral.I3C_EC.TTI.INTERRUPT_ENABLE.IBI_DONE_EN, 1,
                  "enable IBI_DONE interrupt");

      // Exercise the direct W1C path and guarantee a clean starting state.
      // This occurs before either result is generated; terminal status is
      // always read before any post-transaction clear.
      clear_w1c_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 1,
                      "clear stale IBI_DONE without field RMW");
      wait_irq(1'b0, "check initial ACK/NACK IRQ state");
      expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 0,
                   "check initial ACK/NACK IBI_DONE");
      read_field(ral.I3C_EC.TTI.IBI_QUEUE_DEPTH.IBI_QUEUE_DEPTH,
                 field_value, "observe initial ACK/NACK queue depth");

      run_mdb_only_ibi_response(ral, 1'b1, IBI_STATUS_SUCCESS, "ACK");
      run_mdb_only_ibi_response(ral, 1'b0,
                                IBI_STATUS_FAILURE_NACK, "NACK");

      attempt_samples = vseq_ctx.cfg.ibi_cov_attempt_samples -
                        attempt_samples_before;
      completion_samples = vseq_ctx.cfg.ibi_cov_completion_samples -
                           completion_samples_before;
      queue_irq_samples = vseq_ctx.cfg.ibi_cov_queue_irq_samples -
                          queue_irq_samples_before;
      if ((attempt_samples < 2) || (completion_samples < 2) ||
          (queue_irq_samples < 2)) begin
        if (vseq_ctx.cfg.require_ibi_coverage_samples)
          `uvm_fatal("IBI_COVERAGE_WIRING",
                     $sformatf("ACK/NACK coverage is incomplete: attempt=%0d completion=%0d queue_irq=%0d",
                               attempt_samples, completion_samples,
                               queue_irq_samples))
        else
          `uvm_warning("IBI_COVERAGE_WIRING",
                       $sformatf("ACK/NACK functional checks passed with incomplete coverage observation: attempt=%0d completion=%0d queue_irq=%0d",
                                 attempt_samples, completion_samples,
                                 queue_irq_samples))
      end else if ((attempt_samples > 2) || (completion_samples > 2)) begin
        `uvm_warning("IBI_COVERAGE_DUPLICATE",
                     $sformatf("Two IBIs produced extra transaction samples: attempt=%0d completion=%0d (CSR queue_irq snapshots=%0d)",
                               attempt_samples, completion_samples,
                               queue_irq_samples))
      end

      `uvm_info("IBI_ACK_NACK_PASS",
                $sformatf("DUT target completed ACK then first-response NACK IBI: DA=0x%02h MDB=0x%02h",
                          vseq_ctx.cfg.ibi_target_addr,
                          vseq_ctx.cfg.ibi_basic_mdb),
                UVM_LOW)
    end
`else
    `uvm_fatal("IBI_RAL_BUILD",
               "smc_i3c_ibi_target_tx_ack_nack_test requires SMC_USE_I3C_RAL")
`endif
  endtask
endclass : smc_i3c_ibi_target_tx_ack_nack_vseq

`endif // SMC_I3C_IBI_TARGET_TX_ACK_NACK_VSEQ_SV
