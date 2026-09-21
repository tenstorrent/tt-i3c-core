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
// File        : i3c_ibi_scoreboard.sv
// Description : Scoreboard for I3C IBI.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-24
//
// *****************************************************************************

`ifndef I3C_IBI_SCOREBOARD_SV
`define I3C_IBI_SCOREBOARD_SV

`uvm_analysis_imp_decl(_ibi_sb_expected)
`uvm_analysis_imp_decl(_ibi_sb_actual)
`uvm_analysis_imp_decl(_ibi_sb_axi)

class i3c_ibi_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(i3c_ibi_scoreboard)

  uvm_analysis_imp_ibi_sb_expected #(
    i3c_ibi_expected_item, i3c_ibi_scoreboard
  ) expected_export;
  uvm_analysis_imp_ibi_sb_actual #(
    i3c_ibi_actual_item, i3c_ibi_scoreboard
  ) actual_export;
  uvm_analysis_imp_ibi_sb_axi #(
    axi4lite_item #(TB_ADDR_WIDTH, TB_DATA_WIDTH), i3c_ibi_scoreboard
  ) axi_export;
  uvm_analysis_port #(i3c_ibi_item) coverage_port;
  uvm_analysis_port #(i3c_ibi_item) sva_port;

  i3c_env_cfg cfg;

  protected i3c_ibi_expected_item expected_q[$];
  protected i3c_ibi_actual_item actual_q[$];
  protected int unsigned observed_fifo_level;
  protected bit observed_fifo_level_valid;
  protected bit observed_queue_empty;
  protected bit observed_queue_full;
  protected bit observed_queue_state_valid;
  protected int unsigned observed_ibi_threshold;
  protected bit observed_ibi_threshold_valid;
  protected bit response_context_valid;
  protected bit response_ack;
  protected bit [1:0] response_record_kind;
  protected longint unsigned response_transaction_id;

  int unsigned descriptor_count;
  int unsigned actual_count;
  int unsigned passive_count;
  int unsigned irq_count;
  int unsigned completion_count;
  int unsigned match_count;
  int unsigned mismatch_count;

  function new(string name = "i3c_ibi_scoreboard",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    expected_export = new("expected_export", this);
    actual_export = new("actual_export", this);
    axi_export = new("axi_export", this);
    coverage_port = new("coverage_port", this);
    sva_port = new("sva_port", this);
    if ((cfg == null) || (cfg.ral_model == null))
      `uvm_fatal("IBI_SB_CFG",
                 "IBI scoreboard requires env cfg and the I3C RAL model")
  endfunction

  protected function void record_match(string check_name,
                                       longint unsigned transaction_id = 0);
    match_count++;
    `uvm_info("IBI_SB_MATCH",
              $sformatf("%s transaction_id=%0d", check_name, transaction_id),
              UVM_HIGH)
  endfunction

  protected function void record_mismatch(string check_name,
                                           string detail,
                                           longint unsigned transaction_id = 0);
    mismatch_count++;
    cfg.ibi_sb_mismatch_count++;
    `uvm_error("IBI_SB_MISMATCH",
               $sformatf("%s transaction_id=%0d: %s",
                         check_name, transaction_id, detail))
  endfunction

  protected function bit matches_reg(
      axi4lite_item #(TB_ADDR_WIDTH, TB_DATA_WIDTH) item,
      uvm_reg register_handle);
    return item.addr == register_handle.get_address(cfg.ral_model.default_map);
  endfunction

  protected function uvm_reg_data_t extract_field(
      uvm_reg_data_t register_value,
      uvm_reg_field field_handle);
    uvm_reg_data_t field_value;

    field_value = '0;
    for (int unsigned bit_index = 0;
         bit_index < field_handle.get_n_bits(); bit_index++) begin
      field_value[bit_index] =
        register_value[field_handle.get_lsb_pos() + bit_index];
    end
    return field_value;
  endfunction

  protected function string expected_key(i3c_ibi_expected_item item);
    return $sformatf("%0d:%02h:%0d", item.source_instance,
                     item.target_addr, item.source_sequence);
  endfunction

  protected function string actual_key(i3c_ibi_actual_item item);
    return $sformatf("%0d:%02h:%0d", item.source_instance,
                     item.addr, item.source_sequence);
  endfunction

  protected function int find_actual_index(string key);
    foreach (actual_q[i]) begin
      if (actual_key(actual_q[i]) == key)
        return i;
    end
    return -1;
  endfunction

  protected function void compare_byte_stream(
      string source_name,
      i3c_ibi_expected_item expected,
      byte unsigned actual_data[$],
      longint unsigned actual_id,
      int unsigned partial_expected_size);
    int unsigned expected_size;
    bit mismatch;

    // The target owns MDB/payload, but the controller ACK is what permits
    // those bytes onto the bus. A terminal address NACK must be followed by
    // STOP and therefore has an empty host/passive data stream.
    expected_size = expected.expected_ack ?
      (cfg.ibi_expect_partial_data ? partial_expected_size :
       expected.payload_len + (expected.mdb_present ? 1 : 0)) : 0;
    mismatch = (actual_data.size() != expected_size);
    if (!mismatch && expected.expected_ack && expected.mdb_present &&
        (actual_data[0] !== expected.mdb))
      mismatch = 1'b1;
    if (!mismatch && expected.expected_ack) begin
      for (int unsigned index = 0;
           index < (expected_size - (expected.mdb_present ? 1 : 0));
           index++) begin
        if ((index >= expected.payload.size()) ||
            (actual_data[index + (expected.mdb_present ? 1 : 0)] !==
             expected.payload[index])) begin
          mismatch = 1'b1;
          break;
        end
      end
    end

    if (mismatch)
      record_mismatch(
        {source_name, " data"},
        $sformatf("expected_id=%0d actual_id=%0d expected_ack=%0b MDB=0x%02h payload_len=%0d total=%0d actual_total=%0d",
                  expected.transaction_id, actual_id, expected.expected_ack,
                  expected.mdb, expected.payload_len,
                  expected_size, actual_data.size()),
        expected.transaction_id);
    else
      record_match({source_name, " data"}, expected.transaction_id);
  endfunction

  protected function bit [1:0] observed_queue_state();
    if (observed_queue_state_valid && observed_queue_full)
      return 2'd2;
    if (observed_queue_state_valid && observed_queue_empty)
      return 2'd1;
    return 2'd0;
  endfunction

  protected function void emit_queue_coverage(bit [2:0] status_source,
                                               bit [1:0] irq_state);
    i3c_ibi_item item;
    int unsigned free_entries;

    item = i3c_ibi_item::type_id::create("queue_irq_item");
    item.evt_kind = IBI_EVT_QUEUE_IRQ;
    item.transaction_id = response_transaction_id;
    item.queue_record_write = 1'b0;
    item.response_context_valid = response_context_valid;
    item.fifo_level = observed_fifo_level_valid ? observed_fifo_level : 0;
    item.record_kind = response_record_kind;
    item.queue_state = observed_queue_state();
    item.status_source = status_source;
    item.irq_state = irq_state;
    item.role = 1'b0;
    item.irq_enabled = 1'b1;
    item.ack = response_ack;
    item.threshold_relation_valid =
      observed_ibi_threshold_valid && observed_fifo_level_valid &&
      (observed_fifo_level <= cfg.ibi_queue_size);
    if (item.threshold_relation_valid) begin
      free_entries = cfg.ibi_queue_size - observed_fifo_level;
      item.threshold_reached = free_entries >= observed_ibi_threshold;
      if (item.threshold_reached)
        cfg.ibi_cov_threshold_reached_samples++;
      else
        cfg.ibi_cov_threshold_below_samples++;
    end
    coverage_port.write(item);
    cfg.ibi_cov_queue_irq_samples++;
  endfunction

  protected function void emit_sva_completion(
      i3c_ibi_expected_item expected,
      i3c_ibi_actual_item actual);
    i3c_ibi_item item;

    item = i3c_ibi_item::type_id::create("target_sva_completion");
    item.evt_kind = IBI_EVT_COMPLETION;
    item.transaction_id = actual.transaction_id;
    item.attempt_context_valid = actual.attempt_context_valid;
    item.role = 1'b0;
    item.ack = actual.ack;
    item.retry_count = cfg.ibi_retry_count;
    item.terminal_status = actual.terminal_status;
    item.mdb_present = actual.data.size() != 0;
    if (item.mdb_present)
      item.mdb = actual.data[0];
    item.payload_len = item.mdb_present ? actual.data.size() - 1 : 0;
    item.ibi_enabled = actual.ibi_enabled_at_attempt;
    item.reset_error_kind =
      (actual.terminal_status == IBI_STATUS_FAILURE_PARTIAL_DATA) ?
        IBI_ERR_PROTOCOL : IBI_ERR_NONE;
    item.recovery_result =
      (actual.terminal_status == IBI_STATUS_FAILURE_PARTIAL_DATA) ?
        IBI_NOT_RECOVERED : IBI_RECOVERY_NA;
    // A Controller-aborted partial transfer is intentionally shorter than
    // the descriptor. Content equality applies only to completed transfers.
    item.expected_content_valid =
      actual.terminal_status != IBI_STATUS_FAILURE_PARTIAL_DATA;
    item.expected_mdb_present = expected.mdb_present;
    item.expected_mdb = expected.mdb;
    item.expected_payload_len = expected.payload_len;
    sva_port.write(item);
  endfunction

  protected function void compare_transaction(
      i3c_ibi_expected_item expected,
      i3c_ibi_actual_item actual);
    record_match($sformatf("correlation key %s", expected_key(expected)),
                 expected.transaction_id);

    if (actual.addr == expected.target_addr)
      record_match("host address", expected.transaction_id);
    else
      record_mismatch("host address",
                      $sformatf("expected=0x%02h actual=0x%02h actual_id=%0d",
                                expected.target_addr, actual.addr,
                                actual.transaction_id),
                      expected.transaction_id);

    if (actual.ack == expected.expected_ack)
      record_match("host ACK", expected.transaction_id);
    else
      record_mismatch("host ACK",
                      $sformatf("expected=%0b actual=%0b actual_id=%0d",
                                expected.expected_ack, actual.ack,
                                actual.transaction_id),
                      expected.transaction_id);
    compare_byte_stream("host", expected, actual.data,
                        actual.transaction_id,
                        cfg.ibi_partial_host_rx_bytes);

    if (!actual.irq_seen)
      record_mismatch("IBI IRQ", "completion lacks IRQ evidence",
                      expected.transaction_id);
    else begin
      irq_count++;
      record_match("IBI IRQ", expected.transaction_id);
    end

    if (actual.terminal_status == expected.expected_terminal_status)
      record_match("terminal status", expected.transaction_id);
    else
      record_mismatch("terminal status",
                      $sformatf("expected=%s actual=%s",
                                expected.expected_terminal_status.name(),
                                actual.terminal_status.name()),
                      expected.transaction_id);

    emit_sva_completion(expected, actual);

    if (actual.passive_seen) begin
      passive_count++;
      if (actual.passive_ack === actual.ack)
        record_match("passive monitor ACK", expected.transaction_id);
      else
        record_mismatch("passive monitor ACK",
                        $sformatf("host=%0b passive=%0b",
                                  actual.ack, actual.passive_ack),
                        expected.transaction_id);
      compare_byte_stream("passive monitor", expected,
                          actual.passive_data, actual.transaction_id,
                          cfg.ibi_partial_passive_bytes);
    end else if (cfg.require_ibi_passive_monitor_match) begin
      record_mismatch("passive monitor observation",
                      "host-confirmed IBI was not observed passively",
                      expected.transaction_id);
    end

    completion_count++;
    cfg.ibi_sb_completion_count++;
    response_context_valid = 1'b1;
    response_ack = actual.ack;
    response_record_kind = expected.expected_ack ? 2'd1 : 2'd0;
    response_transaction_id = actual.transaction_id;
  endfunction

  protected function void compare_pending();
    i3c_ibi_expected_item expected;
    i3c_ibi_actual_item actual;
    int expected_index;
    int actual_index;

    // Different targets may complete out of descriptor order. Match by the
    // protocol-derived per-source key, preserving FIFO only within one source.
    expected_index = 0;
    while ((expected_index < expected_q.size()) &&
           (actual_q.size() != 0)) begin
      actual_index = find_actual_index(expected_key(expected_q[expected_index]));
      if (actual_index < 0) begin
        expected_index++;
      end else begin
        expected = expected_q[expected_index];
        actual = actual_q[actual_index];
        expected_q.delete(expected_index);
        actual_q.delete(actual_index);
        compare_transaction(expected, actual);
        expected_index = 0;
      end
    end
  endfunction

  virtual function void write_ibi_sb_expected(
      i3c_ibi_expected_item item);
    i3c_ibi_expected_item expected;

    if (item == null)
      return;
    expected = i3c_ibi_expected_item::type_id::create("expected_copy");
    expected.copy(item);
    expected_q.push_back(expected);
    descriptor_count++;
    compare_pending();
  endfunction

  virtual function void write_ibi_sb_actual(i3c_ibi_actual_item item);
    i3c_ibi_actual_item actual;

    if (item == null)
      return;
    actual = i3c_ibi_actual_item::type_id::create("actual_copy");
    actual.copy(item);
    actual_q.push_back(actual);
    actual_count++;
    compare_pending();
  endfunction

  virtual function void write_ibi_sb_axi(
      axi4lite_item #(TB_ADDR_WIDTH, TB_DATA_WIDTH) item);
    uvm_reg_data_t depth_value;
    uvm_reg_data_t empty_value;
    uvm_reg_data_t full_value;
    uvm_reg_data_t done_value;
    uvm_reg_data_t threshold_value;
    uvm_reg_data_t pending_value;
    bit [1:0] irq_state;

    if ((item == null) || (item.resp != 2'b00))
      return;

    irq_state = (cfg.vif.i3c_irq === 1'b1) ? 2'd1 : 2'd0;

    if (item.write &&
        matches_reg(item, cfg.ral_model.I3C_EC.TTI.INTERRUPT_STATUS)) begin
      done_value = extract_field(
        item.data, cfg.ral_model.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE);
      threshold_value = extract_field(
        item.data,
        cfg.ral_model.I3C_EC.TTI.INTERRUPT_STATUS.IBI_THLD_STAT);
      if (done_value[0])
        emit_queue_coverage(3'd2, 2'd2);
      if (threshold_value[0])
        emit_queue_coverage(3'd0, 2'd2);
      return;
    end

    if (item.write &&
        matches_reg(item, cfg.ral_model.I3C_EC.TTI.QUEUE_THLD_CTRL)) begin
      threshold_value = extract_field(
        item.data, cfg.ral_model.I3C_EC.TTI.QUEUE_THLD_CTRL.IBI_THLD);
      observed_ibi_threshold = int'(threshold_value);
      observed_ibi_threshold_valid = observed_ibi_threshold != 0;
      return;
    end

    if (item.write)
      return;

    if (matches_reg(item, cfg.ral_model.I3C_EC.TTI.IBI_QUEUE_DEPTH)) begin
      depth_value = extract_field(
        item.rdata, cfg.ral_model.I3C_EC.TTI.IBI_QUEUE_DEPTH.IBI_QUEUE_DEPTH);
      observed_fifo_level = int'(depth_value);
      observed_fifo_level_valid = 1'b1;
      if (observed_fifo_level <= cfg.ibi_queue_size)
        record_match("IBI queue depth is within decoded capacity");
      else
        record_mismatch("IBI queue depth",
                        $sformatf("capacity=%0d observed=%0d",
                                  cfg.ibi_queue_size, observed_fifo_level));
      emit_queue_coverage(3'd4, irq_state);
      return;
    end

    if (matches_reg(item, cfg.ral_model.I3C_EC.TTI.QUEUE_STATUS)) begin
      empty_value = extract_field(
        item.rdata, cfg.ral_model.I3C_EC.TTI.QUEUE_STATUS.IBI_QUEUE_EMPTY);
      full_value = extract_field(
        item.rdata, cfg.ral_model.I3C_EC.TTI.QUEUE_STATUS.IBI_QUEUE_FULL);
      observed_queue_empty = empty_value[0];
      observed_queue_full = full_value[0];
      observed_queue_state_valid = 1'b1;
      if (observed_queue_empty && observed_queue_full)
        record_mismatch("IBI queue flags",
                        "IBI_QUEUE_EMPTY and IBI_QUEUE_FULL are both set");
      else
        record_match("IBI queue flags are mutually exclusive");
      emit_queue_coverage(observed_queue_full ? 3'd1 : 3'd4, irq_state);
      return;
    end

    if (matches_reg(item, cfg.ral_model.I3C_EC.TTI.INTERRUPT_STATUS)) begin
      done_value = extract_field(
        item.rdata, cfg.ral_model.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE);
      threshold_value = extract_field(
        item.rdata,
        cfg.ral_model.I3C_EC.TTI.INTERRUPT_STATUS.IBI_THLD_STAT);
      pending_value = extract_field(
        item.rdata, cfg.ral_model.I3C_EC.TTI.INTERRUPT_STATUS.PENDING_IBI);
      if (done_value[0])
        emit_queue_coverage(3'd2, irq_state);
      if (threshold_value[0])
        emit_queue_coverage(3'd0, irq_state);
      if (pending_value != 0)
        emit_queue_coverage(3'd4, irq_state);
    end
  endfunction

  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (expected_q.size() != 0)
      record_mismatch("pending expected transactions",
                      $sformatf("%0d descriptor prediction(s) lack actual completion",
                                expected_q.size()));
    if (actual_q.size() != 0)
      record_mismatch("pending actual transactions",
                      $sformatf("%0d actual completion(s) lack descriptor prediction",
                                actual_q.size()));
    if (actual_count != descriptor_count)
      record_mismatch("expected/actual balance",
                      $sformatf("descriptors=%0d actual_completions=%0d",
                                descriptor_count, actual_count));
    if (completion_count != descriptor_count)
      record_mismatch("descriptor/completion balance",
                      $sformatf("descriptors=%0d compared_completions=%0d",
                                descriptor_count, completion_count));
    if (irq_count != descriptor_count)
      record_mismatch("descriptor/IRQ balance",
                      $sformatf("descriptors=%0d IRQs=%0d",
                                descriptor_count, irq_count));
    if (cfg.vif.i3c_irq !== 1'b0)
      record_mismatch("final IRQ state", "i3c_irq did not return low");
    if (cfg.require_ibi_passive_monitor_match &&
        (passive_count != actual_count))
      record_mismatch("actual/passive balance",
                      $sformatf("actual=%0d passive=%0d",
                                actual_count, passive_count));
  endfunction

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("IBI_SB_SUMMARY",
              $sformatf("descriptors=%0d actual=%0d passive=%0d IRQs=%0d completions=%0d matches=%0d mismatches=%0d",
                        descriptor_count, actual_count, passive_count,
                        irq_count, completion_count, match_count,
                        mismatch_count),
              UVM_LOW)
    if (mismatch_count == 0)
      `uvm_info("IBI_SB_SUMMARY", "PASSED: zero mismatches", UVM_LOW)
    else
      `uvm_error("IBI_SB_SUMMARY",
                 $sformatf("FAILED: %0d mismatch(es)", mismatch_count))
  endfunction
endclass : i3c_ibi_scoreboard

`endif // I3C_IBI_SCOREBOARD_SV
