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
// File        : smc_i3c_ibi_target_tx_mdb_payload_vseq.sv
// Description : Virtual sequence for I3C IBI MDB payload.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-24
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_TARGET_TX_MDB_PAYLOAD_VSEQ_SV
`define SMC_I3C_IBI_TARGET_TX_MDB_PAYLOAD_VSEQ_SV

class smc_i3c_ibi_target_tx_mdb_payload_vseq extends smc_i3c_ibi_base_vseq;
  `uvm_object_utils(smc_i3c_ibi_target_tx_mdb_payload_vseq)

  function new(string name = "smc_i3c_ibi_target_tx_mdb_payload_vseq");
    super.new(name);
  endfunction

`ifdef SMC_USE_I3C_RTL
`ifdef SMC_USE_I3C_RAL
  // One ACKed IBI carrying MDB + payload_len data bytes. The payload is a
  // deterministic ramp so a byte-order or off-by-one error in the target data
  // path surfaces as a scoreboard mismatch rather than passing by luck.
  protected task run_payload_ibi(input smc_i3c_ral_model ral,
                                 input int unsigned payload_len,
                                 input bit [7:0] mdb,
                                 input string phase_name);
    smc_i3c_host_respond_ibi_seq host_seq;
    uvm_event host_armed_event;
    uvm_reg_data_t field_value;
    uvm_reg_data_t ibi_descriptor;
    uvm_reg_data_t payload_word;
    // Hold the expected status in a typed variable: calling .name() directly on
    // the wildcard-imported enum literal makes VCS treat it as a hierarchical
    // reference and raises XMRE, whereas a variable resolves the method cleanly.
    ibi_terminal_status_e expected_status;
    byte unsigned payload_bytes[$];
    int unsigned payload_words;
    int unsigned byte_index;
    bit transaction_done;
    bit status_captured;
    int unsigned completion_before;
    int unsigned mismatch_before;

    if (payload_len == 0)
      `uvm_fatal("IBI_PAYLOAD_LEN",
                 "run_payload_ibi requires a non-zero payload length")
    if (payload_len > 8'hff)
      `uvm_fatal("IBI_PAYLOAD_LEN",
                 $sformatf("payload_len 0x%0h exceeds the 8-bit descriptor field",
                           payload_len))

    completion_before = vseq_ctx.cfg.ibi_sb_completion_count;
    mismatch_before = vseq_ctx.cfg.ibi_sb_mismatch_count;
    // The payload IBI is always ACKed; the target owns MDB + payload and the
    // expected byte stream is reconstructed by the predictor from the writes.
    vseq_ctx.cfg.ibi_expected_ack = 1'b1;
    expected_status = vseq_ctx.cfg.ibi_expect_partial_data ?
      IBI_STATUS_FAILURE_PARTIAL_DATA : IBI_STATUS_SUCCESS;
    vseq_ctx.cfg.ibi_expected_terminal_status = expected_status;

    payload_bytes.delete();
    for (byte_index = 0; byte_index < payload_len; byte_index++)
      payload_bytes.push_back(8'hc0 + byte_index[7:0]);

    host_seq = smc_i3c_host_respond_ibi_seq::type_id::create(
      $sformatf("%s_host_seq", phase_name));
    host_seq.ibi_ack = 1'b1;
    // In partial-data mode the Host deliberately stops after an initial byte
    // prefix while the descriptor advertises more. The unmodified VIP emits a
    // repeated START after sampling a continuation T-bit, which is the I3C
    // Controller-abort mechanism observed by the DUT Target FSM.
    host_seq.rx_byte_count = vseq_ctx.cfg.ibi_expect_partial_data ?
      vseq_ctx.cfg.ibi_partial_host_rx_bytes : payload_len + 1;

    // Descriptor: [31:24]=MDB, [7:0]=payload byte count. Payload bytes follow
    // in little-endian order within each subsequent IBI_PORT word.
    ibi_descriptor = (uvm_reg_data_t'(mdb) << 24) |
                     uvm_reg_data_t'(payload_len[7:0]);
    payload_words = (payload_len + 3) / 4;

    host_armed_event = uvm_event_pool::get_global(
      SMC_I3C_HOST_IBI_ARMED_EVENT);
    host_armed_event.reset();
    transaction_done = 1'b0;
    status_captured = 1'b0;

    fork : ibi_payload_timeout_guard
      begin
        fork
          host_seq.start(vseq_ctx.i3c_sqr);
          begin
            host_armed_event.wait_on();
            write_register(ral.I3C_EC.TTI.IBI_PORT, ibi_descriptor,
                           $sformatf("queue %s IBI descriptor (MDB+%0d payload)",
                                     phase_name, payload_len));
            for (int unsigned word_index = 0; word_index < payload_words;
                 word_index++) begin
              payload_word = '0;
              for (int unsigned lane = 0; lane < 4; lane++) begin
                int unsigned flat;
                flat = (word_index * 4) + lane;
                if (flat < payload_len)
                  payload_word[8*lane +: 8] = payload_bytes[flat];
              end
              write_register(ral.I3C_EC.TTI.IBI_PORT, payload_word,
                             $sformatf("queue %s payload word %0d",
                                       phase_name, word_index));
            end
          end
          begin
            wait_irq(1'b1,
                     $sformatf("wait for %s IBI_DONE IRQ", phase_name));
            expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 1,
                         $sformatf("confirm %s IBI_DONE source", phase_name));
            read_field(ral.I3C_EC.TTI.STATUS.LAST_IBI_STATUS, field_value,
                       $sformatf("capture %s LAST_IBI_STATUS", phase_name));
            status_captured = 1'b1;
            if (field_value != uvm_reg_data_t'(expected_status))
              `uvm_fatal("IBI_TERMINAL_STATUS",
                         $sformatf("%s expected status=%s (0x%0h), actual=0x%0h",
                                   phase_name, expected_status.name(),
                                   expected_status, field_value))
          end
        join
        transaction_done = 1'b1;
      end
      begin
        repeat (vseq_ctx.cfg.ibi_timeout_cycles)
          @(posedge vseq_ctx.cfg.vif.clk);
        if (!transaction_done)
          `uvm_fatal("IBI_PAYLOAD_TIMEOUT",
                     $sformatf("Timed out waiting for %s IBI completion",
                               phase_name))
      end
    join_any
    disable ibi_payload_timeout_guard;

    if (!transaction_done || !host_seq.response_valid || !status_captured)
      `uvm_fatal("IBI_HOST_CHECK",
                 $sformatf("%s IBI did not complete all required observations: host=%0b status=%0b",
                           phase_name, host_seq.response_valid,
                           status_captured))

    wait_irq(1'b0,
             $sformatf("wait for %s IRQ clear after status read", phase_name));
    expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 0,
                 $sformatf("check cleared %s IBI_DONE", phase_name));
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
                 "smc_i3c_ibi_target_tx_mdb_payload_test requires DUT_MODE=rtl")
    if (vseq_ctx.cfg.ibi_dut_role != SMC_I3C_IBI_DUT_TARGET)
      `uvm_fatal("IBI_PAYLOAD_ROLE",
                 "smc_i3c_ibi_target_tx_mdb_payload_test covers DUT-target transmit only")
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
      int unsigned expected_transactions;
      smc_i3c_ibi_recovery_checker recovery_checker;
      bit recovery_completed;
      bit recovery_passed;
      // Close every payload-length bucket deterministically.  The one-byte
      // vector uses MDB group 101 so pending-read content is demonstrated by
      // the real Target transmit path instead of depending on a random seed.
      // First four entries close every payload-length bucket with group 101.
      // The remaining entries cross groups 000 and 001 with short, medium and
      // long payloads. All ten transactions traverse the real Target FIFO,
      // Host response, STATUS, IRQ, passive observer and scoreboard paths.
      int unsigned payload_lengths[10] =
        '{1, 3, 6, 10, 3, 6, 10, 3, 6, 10};
      bit [7:0] mdb_values[10] =
        '{8'ha0, 8'ha5, 8'ha5, 8'ha5,
          8'h01, 8'h01, 8'h01,
          8'h21, 8'h21, 8'h21};

      if (vseq_ctx.i3c_sqr == null)
        `uvm_fatal("IBI_HOST_SQR", "I3C host sequencer is not available")
      if (!vseq_ctx.cfg.has_ibi_scoreboard)
        `uvm_fatal("IBI_SCOREBOARD_CFG",
                   "MDB payload test requires the IBI scoreboard")

      ral = get_i3c_ral_model();
      attempt_samples_before = vseq_ctx.cfg.ibi_cov_attempt_samples;
      completion_samples_before = vseq_ctx.cfg.ibi_cov_completion_samples;
      queue_irq_samples_before = vseq_ctx.cfg.ibi_cov_queue_irq_samples;

      initialize_target_ibi(ral);
      write_field(ral.I3C_EC.TTI.INTERRUPT_ENABLE.IBI_DONE_EN, 1,
                  "enable IBI_DONE interrupt");
      clear_w1c_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 1,
                      "clear stale IBI_DONE without field RMW");
      wait_irq(1'b0, "check initial payload IRQ state");
      expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 0,
                   "check initial payload IBI_DONE");
      read_field(ral.I3C_EC.TTI.IBI_QUEUE_DEPTH.IBI_QUEUE_DEPTH,
                 field_value, "observe initial payload queue depth");

      if (vseq_ctx.cfg.ibi_expect_partial_data) begin
        recovery_checker = vseq_ctx.i3c_ibi_recovery_checker;
        if (recovery_checker == null)
          `uvm_fatal("IBI_PARTIAL_RECOVERY",
                     "Partial-data recovery checker is unavailable")
        recovery_checker.arm_recovery(IBI_ERR_PROTOCOL, 1'b0, 1'b1);
        run_payload_ibi(ral, 6, 8'h21, "PARTIAL_AFTER_TWO_BYTE_PREFIX");

        write_action_field(ral.I3C_EC.TTI.RESET_CONTROL.IBI_QUEUE_RST, 1,
                           "reset Target IBI queue after partial transfer");
        wait_field_value(ral.I3C_EC.TTI.RESET_CONTROL.IBI_QUEUE_RST, 0,
                         "wait for partial-transfer queue reset self-clear");
        expect_field(ral.I3C_EC.TTI.QUEUE_STATUS.IBI_QUEUE_EMPTY, 1,
                     "confirm empty queue after partial-transfer cleanup");

        vseq_ctx.cfg.ibi_expect_partial_data = 1'b0;
        run_payload_ibi(ral, 3, 8'h21, "POST_PARTIAL_FORWARD_PROGRESS");
        recovery_checker.wait_for_result(
          vseq_ctx.cfg.ibi_timeout_cycles,
          recovery_completed, recovery_passed);
        if (!recovery_completed || !recovery_passed)
          `uvm_fatal("IBI_PARTIAL_RECOVERY",
                     "Target did not recover after partial-data IBI")
        expected_transactions = 2;
      end else begin
        foreach (payload_lengths[i])
          run_payload_ibi(ral, payload_lengths[i], mdb_values[i],
                          $sformatf("PAYLOAD_%0d_GRP_%03b",
                                    payload_lengths[i], mdb_values[i][7:5]));
        expected_transactions = $size(payload_lengths);
      end

      attempt_samples = vseq_ctx.cfg.ibi_cov_attempt_samples -
                        attempt_samples_before;
      completion_samples = vseq_ctx.cfg.ibi_cov_completion_samples -
                           completion_samples_before;
      queue_irq_samples = vseq_ctx.cfg.ibi_cov_queue_irq_samples -
                          queue_irq_samples_before;
      if ((attempt_samples < expected_transactions) ||
          (completion_samples < expected_transactions) ||
          (queue_irq_samples < expected_transactions)) begin
        if (vseq_ctx.cfg.require_ibi_coverage_samples)
          `uvm_fatal("IBI_COVERAGE_WIRING",
                     $sformatf("Payload coverage is incomplete: attempt=%0d completion=%0d queue_irq=%0d expected>=%0d",
                               attempt_samples, completion_samples,
                               queue_irq_samples, expected_transactions))
        else
          `uvm_warning("IBI_COVERAGE_WIRING",
                       $sformatf("Payload functional checks passed with incomplete coverage observation: attempt=%0d completion=%0d queue_irq=%0d",
                                 attempt_samples, completion_samples,
                                 queue_irq_samples))
      end else if ((attempt_samples > expected_transactions) ||
                   (completion_samples > expected_transactions)) begin
        `uvm_warning("IBI_COVERAGE_DUPLICATE",
                     $sformatf("Payload IBIs produced extra transaction samples: attempt=%0d completion=%0d (CSR queue_irq snapshots=%0d)",
                               attempt_samples, completion_samples,
                               queue_irq_samples))
      end

      `uvm_info("IBI_MDB_PAYLOAD_PASS",
                $sformatf("DUT target transmitted MDB+payload IBIs (lengths=%p MDBs=%p): DA=0x%02h",
                          payload_lengths, mdb_values,
                          vseq_ctx.cfg.ibi_target_addr),
                UVM_LOW)
    end
`else
    `uvm_fatal("IBI_RAL_BUILD",
               "smc_i3c_ibi_target_tx_mdb_payload_test requires SMC_USE_I3C_RAL")
`endif
  endtask
endclass : smc_i3c_ibi_target_tx_mdb_payload_vseq

`endif // SMC_I3C_IBI_TARGET_TX_MDB_PAYLOAD_VSEQ_SV
