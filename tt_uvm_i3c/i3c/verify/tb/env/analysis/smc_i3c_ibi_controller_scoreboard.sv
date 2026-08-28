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
// File        : smc_i3c_ibi_controller_scoreboard.sv
// Description : Scoreboard for I3C IBI controller.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-06
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_CONTROLLER_SCOREBOARD_SV
`define SMC_I3C_IBI_CONTROLLER_SCOREBOARD_SV

`uvm_analysis_imp_decl(_ibi_ctrl_sb_expected)
`uvm_analysis_imp_decl(_ibi_ctrl_sb_actual)
`uvm_analysis_imp_decl(_ibi_ctrl_sb_axi)

class smc_i3c_ibi_controller_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(smc_i3c_ibi_controller_scoreboard)

  uvm_analysis_imp_ibi_ctrl_sb_expected #(
    smc_i3c_ibi_expected_item,
    smc_i3c_ibi_controller_scoreboard
  ) expected_export;
  uvm_analysis_imp_ibi_ctrl_sb_actual #(
    smc_i3c_ibi_controller_actual_item,
    smc_i3c_ibi_controller_scoreboard
  ) actual_export;
  uvm_analysis_imp_ibi_ctrl_sb_axi #(
    axi4lite_item #(TB_ADDR_WIDTH, TB_DATA_WIDTH),
    smc_i3c_ibi_controller_scoreboard
  ) axi_export;
  uvm_analysis_port #(smc_i3c_ibi_item) coverage_port;

  smc_peripherals_env_cfg cfg;
  protected smc_i3c_ibi_expected_item expected_q[$];
  protected smc_i3c_ibi_controller_actual_item actual_q[$];
  int unsigned match_count;
  int unsigned mismatch_count;
  protected bit pio_transfer_error_assert_seen;
  protected bit pio_transfer_error_clear_pending;

  function new(string name = "smc_i3c_ibi_controller_scoreboard",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    expected_export = new("expected_export", this);
    actual_export = new("actual_export", this);
    axi_export = new("axi_export", this);
    coverage_port = new("coverage_port", this);
    if (cfg == null)
      `uvm_fatal("IBI_CTRL_SB_CFG",
                 "Controller scoreboard requires environment config")
  endfunction

  protected function bit matches_reg(
      axi4lite_item #(TB_ADDR_WIDTH, TB_DATA_WIDTH) item,
      uvm_reg register_handle);
    return item.addr == register_handle.get_address(
      cfg.ral_model.default_map);
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

  protected function string expected_key(smc_i3c_ibi_expected_item item);
    return $sformatf("%02h:%0d", item.target_addr,
                     item.source_sequence);
  endfunction

  protected function string actual_key(
      smc_i3c_ibi_controller_actual_item item);
    return $sformatf("%02h:%0d", item.addr, item.source_sequence);
  endfunction

  protected function int find_actual(string key);
    foreach (actual_q[index]) begin
      if (actual_key(actual_q[index]) == key)
        return index;
    end
    return -1;
  endfunction

  protected function void mismatch(string name, string detail);
    mismatch_count++;
    cfg.ibi_sb_mismatch_count++;
    `uvm_error("IBI_CTRL_SB_MISMATCH",
               $sformatf("%s: %s", name, detail))
  endfunction

  protected function void match(string name);
    match_count++;
    `uvm_info("IBI_CTRL_SB_MATCH", name, UVM_HIGH)
  endfunction

  // Publish the lifecycle of the real PIO transfer-error interrupt exercised
  // by the Controller FIFO/IRQ test.  This is an IRQ/status observation, not
  // an IBI queue error descriptor: the DUT does not enqueue an IBI REC_ERROR
  // record for PIO_INTR_FORCE.
  protected function void emit_pio_transfer_error_irq(
      input bit [1:0] irq_state);
    smc_i3c_ibi_item item;

    item = smc_i3c_ibi_item::type_id::create(
      "controller_pio_transfer_error_irq");
    item.evt_kind = IBI_EVT_QUEUE_IRQ;
    item.role = 1'b1;
    item.fifo_level = 0;
    item.record_kind = 2'd0;
    item.queue_state = 2'd1;
    item.status_source = 3'd3;
    item.irq_state = irq_state;
    // The lifecycle is emitted only from the FIFO/IRQ scenario after software
    // enables TRANSFER_ERR_SIGNAL_EN. Preserve that architectural enable
    // context so the integration SVA distinguishes a legitimate asserted IRQ
    // from an interrupt that escaped its mask.
    item.irq_enabled =
      cfg.ral_model.PIOControl.PIO_INTR_SIGNAL_ENABLE.
        TRANSFER_ERR_SIGNAL_EN.get_mirrored_value() != 0;
    item.queue_record_write = 1'b0;
    item.response_context_valid = 1'b0;
    item.threshold_relation_valid = 1'b0;
    coverage_port.write(item);
    cfg.ibi_cov_queue_irq_samples++;
  endfunction

  protected function void compare_bytes(
      string source,
      smc_i3c_ibi_expected_item expected,
      byte unsigned actual[$]);
    int unsigned expected_size;
    bit failed;

    expected_size = expected.expected_ack ?
      ((expected.mdb_present ? 1 : 0) + expected.payload_len) : 0;
    failed = actual.size() != expected_size;
    // A rejected IBI transfers no bytes. MDB and payload describe what the
    // Target intended to send, not data expected in the Controller FIFO.
    if (!failed && expected.expected_ack && expected.mdb_present &&
        (actual[0] !== expected.mdb))
      failed = 1'b1;
    if (!failed && expected.expected_ack) begin
      for (int unsigned index = 0;
           index < expected.payload_len; index++) begin
        if ((index >= expected.payload.size()) ||
            (actual[index + (expected.mdb_present ? 1 : 0)] !==
             expected.payload[index])) begin
          failed = 1'b1;
          break;
        end
      end
    end
    if (failed)
      mismatch({source, " data"},
               $sformatf("expected bytes=%0d MDB=0x%02h payload=%0d actual bytes=%0d",
                         expected_size, expected.mdb,
                         expected.payload_len, actual.size()));
    else
      match({source, " data"});
  endfunction

  protected function void emit_coverage(
      smc_i3c_ibi_expected_item expected,
      smc_i3c_ibi_controller_actual_item actual);
    smc_i3c_ibi_item item;

    item = smc_i3c_ibi_item::type_id::create("controller_attempt");
    item.evt_kind = IBI_EVT_ATTEMPT;
    item.transaction_id = expected.transaction_id;
    item.role = 1'b1;
    item.src_instance = expected.source_instance;
    item.ibi_addr = expected.target_addr;
    item.addr_class = cfg.ibi_addr_class;
    item.addr_class_valid = cfg.ibi_addr_class_valid;
    item.bcr = cfg.ibi_bcr;
    item.ibi_enabled = expected.ibi_enabled;
    item.requester_count = cfg.ibi_requester_count;
    item.arb_outcome = cfg.ibi_arb_outcome;
    item.bus_state = cfg.ibi_bus_state;
    coverage_port.write(item);
    cfg.ibi_cov_attempt_samples++;

    item = smc_i3c_ibi_item::type_id::create("controller_completion");
    item.evt_kind = IBI_EVT_COMPLETION;
    item.transaction_id = expected.transaction_id;
    item.attempt_context_valid = 1'b1;
    item.role = 1'b1;
    item.ack = actual.ack;
    item.retry_count = cfg.ibi_retry_count;
    if (actual.error)
      item.terminal_status = IBI_STATUS_FAILURE_PARTIAL_DATA;
    else if (actual.ibi_status)
      item.terminal_status = IBI_STATUS_FAILURE_NACK;
    else
      item.terminal_status = IBI_STATUS_SUCCESS;
    item.mdb_present = actual.hci_data.size() != 0;
    if (item.mdb_present)
      item.mdb = actual.hci_data[0];
    item.payload_len = item.mdb_present ?
      actual.hci_data.size() - 1 : 0;
    item.dat_match = expected.dat_match;
    item.payload_policy = expected.payload_policy;
    item.reset_error_kind = actual.error ?
      IBI_ERR_PROTOCOL : IBI_ERR_NONE;
    item.recovery_result = actual.error ?
      IBI_NOT_RECOVERED : IBI_RECOVERY_NA;
    item.expected_content_valid = 1'b1;
    item.expected_mdb_present = expected.mdb_present;
    item.expected_mdb = expected.mdb;
    item.expected_payload_len = expected.payload_len;
    item.arb_outcome = cfg.ibi_arb_outcome;
    item.ibi_enabled = expected.ibi_enabled;
    coverage_port.write(item);
    cfg.ibi_cov_completion_samples++;

    item = smc_i3c_ibi_item::type_id::create("controller_queue_irq");
    item.evt_kind = IBI_EVT_QUEUE_IRQ;
    item.transaction_id = expected.transaction_id;
    // A rejected/NACKed notification must not be represented as a committed
    // HCI record.  Keep the response context so policy SVA can observe the
    // rejection while qualifying record publication with the bus response.
    item.queue_record_write = actual.ack;
    item.response_context_valid = 1'b1;
    item.ack = actual.ack;
    // The Controller HCI exposes the queued record, but no direct occupancy
    // CSR. For this single-IBI scenario, enqueue occupancy is the observed
    // status descriptor plus its observed payload DWORDs.
    item.fifo_level = 1 + ((actual.data_length + 3) / 4);
    item.record_kind = (actual.hci_data.size() != 0) ? 2'd1 : 2'd0;
    // The pinned Controller prevents overflow by NACKing an IBI when the
    // response queue has no descriptor space. Represent that observable full
    // rejection, not an overflow/error record that the DUT cannot publish.
    item.queue_state = expected.queue_full_reject ? 2'd2 : 2'd0;
    // The Controller exposes a regular HCI IBI record for every accepted
    // notification. Preserve the protocol classification in the normalized
    // queue event: MDB group 101 is Pending Read; other records use the normal
    // threshold source. This lets SVA correlate completion and queue snapshots
    // without inventing a separate RTL status bit.
    item.status_source =
      (actual.hci_data.size() != 0) &&
      (actual.hci_data[0][7:5] == 3'b101) ? 3'd4 : 3'd0;
    // For a masked attempt, use the IRQ pin sampled with the target
    // observation. actual.irq_seen is cumulative and may become true only
    // after software unmasks the threshold signal and drains the record.
    item.irq_state = expected.irq_enabled_at_attempt ?
      (actual.irq_seen ? 2'd1 : 2'd0) :
      (expected.irq_asserted_at_attempt ? 2'd1 : 2'd0);
    item.role = 1'b1;
    item.irq_enabled = expected.irq_enabled_at_attempt;
    item.threshold_relation_valid = 1'b1;
    item.threshold_reached = (item.irq_state == 2'd1);
    coverage_port.write(item);
    cfg.ibi_cov_queue_irq_samples++;
    cfg.ibi_cov_threshold_reached_samples++;
  endfunction

  protected function void compare_pair(
      smc_i3c_ibi_expected_item expected,
      smc_i3c_ibi_controller_actual_item actual);
    int unsigned expected_bytes;

    expected_bytes = expected.expected_ack ?
      (expected.mdb_present ? 1 : 0) + expected.payload_len : 0;
    if (actual.addr !== expected.target_addr)
      mismatch("source address",
               $sformatf("expected=0x%02h actual=0x%02h",
                         expected.target_addr, actual.addr));
    else
      match("source address");
    if (actual.ack !== expected.expected_ack)
      mismatch("controller ACK",
               $sformatf("expected=%0b actual=%0b",
                         expected.expected_ack, actual.ack));
    else
      match("controller ACK");
    if (!actual.arbitration_won)
      mismatch("arbitration", "target did not win IBI address arbitration");
    else
      match("arbitration");
    if (actual.ibi_id !== {expected.target_addr, 1'b1})
      mismatch("HCI IBI_ID",
               $sformatf("expected=0x%02h actual=0x%02h",
                         {expected.target_addr, 1'b1}, actual.ibi_id));
    else
      match("HCI IBI_ID");
    if (actual.data_length != expected_bytes)
      mismatch("HCI DATA_LENGTH",
               $sformatf("expected=%0d actual=%0d",
                         expected_bytes, actual.data_length));
    else
      match("HCI DATA_LENGTH");
    if (actual.status_type !== expected.expected_status_type)
      mismatch("HCI STATUS_TYPE",
               $sformatf("expected=0x%0h (%s) actual=0x%0h",
                         expected.expected_status_type,
                         (expected.expected_status_type == 3'b100) ?
                           "AutoCmdIBI" : "RegularIBI",
                         actual.status_type));
    else
      match("HCI STATUS_TYPE");
    if (!actual.last_status)
      mismatch("HCI LAST_STATUS",
               "single-record IBI must mark the final status descriptor");
    else
      match("HCI LAST_STATUS");
    if (actual.timestamp)
      mismatch("HCI timestamp",
               "DAT timestamping is disabled but TS is set");
    else
      match("HCI timestamp");
    if (actual.chunks != 0)
      mismatch("HCI chunks",
               $sformatf("single status descriptor expected chunks=0 actual=%0d",
                         actual.chunks));
    else
      match("HCI chunks");
    if (actual.error)
      mismatch("HCI error", "descriptor error bit is set");
    else
      match("HCI error");
    if (actual.ibi_status !== !expected.expected_ack)
      mismatch("HCI IBI_STATUS",
               $sformatf("expected=%0b actual=%0b",
                         !expected.expected_ack, actual.ibi_status));
    else
      match("HCI IBI_STATUS");
    if (cfg.require_ibi_controller_record_irq) begin
      if (!actual.irq_seen)
        mismatch("IRQ", "IBI record was not accompanied by IRQ");
      else
        match("IRQ");
    end

    compare_bytes("HCI FIFO", expected, actual.hci_data);
    if (expected.mdb_present && (actual.hci_data.size() != 0)) begin
      if (actual.hci_data[0][7:5] !== expected.mdb[7:5])
        mismatch("MDB group classification",
                 $sformatf("expected group=%03b actual group=%03b",
                           expected.mdb[7:5], actual.hci_data[0][7:5]));
      else
        match("MDB group classification");
    end
    if (cfg.require_ibi_passive_monitor_match) begin
      if (!actual.passive_seen)
        mismatch("passive monitor", "no correlated passive bus item");
      else begin
        if (actual.passive_ack !== expected.expected_ack)
          mismatch("passive ACK",
                   $sformatf("expected=%0b actual=%0b",
                             expected.expected_ack, actual.passive_ack));
        else
          match("passive ACK");
        compare_bytes("passive monitor", expected, actual.passive_data);
      end
    end

    emit_coverage(expected, actual);
    cfg.ibi_sb_completion_count++;
  endfunction

  protected function void correlate();
    int actual_index;

    for (int expected_index = int'(expected_q.size()) - 1;
         expected_index >= 0; expected_index--) begin
      actual_index = find_actual(expected_key(expected_q[expected_index]));
      if (actual_index >= 0) begin
        compare_pair(expected_q[expected_index], actual_q[actual_index]);
        expected_q.delete(expected_index);
        actual_q.delete(actual_index);
      end
    end
  endfunction

  virtual function void write_ibi_ctrl_sb_expected(
      smc_i3c_ibi_expected_item item);
    if (item != null) begin
      expected_q.push_back(item);
      correlate();
    end
  endfunction

  virtual function void write_ibi_ctrl_sb_actual(
      smc_i3c_ibi_controller_actual_item item);
    if (item != null) begin
      actual_q.push_back(item);
      correlate();
    end
  endfunction

  virtual function void write_ibi_ctrl_sb_axi(
      axi4lite_item #(TB_ADDR_WIDTH, TB_DATA_WIDTH) item);
    uvm_reg_data_t reset_value;
    uvm_reg_data_t register_value;
    uvm_reg_data_t field_value;

    if ((item == null) || (item.resp != 2'b00))
      return;

    register_value = item.write ? item.data : item.rdata;

    if (item.write &&
        matches_reg(item, cfg.ral_model.PIOControl.PIO_INTR_FORCE)) begin
      field_value = extract_field(
        register_value,
        cfg.ral_model.PIOControl.PIO_INTR_FORCE.TRANSFER_ERR_FORCE);
      if (field_value[0])
        emit_pio_transfer_error_irq(2'd3);
      return;
    end

    if (item.write &&
        matches_reg(item, cfg.ral_model.PIOControl.PIO_INTR_STATUS)) begin
      field_value = extract_field(
        register_value,
        cfg.ral_model.PIOControl.PIO_INTR_STATUS.TRANSFER_ERR_STAT);
      if (field_value[0])
        pio_transfer_error_clear_pending = 1'b1;
      return;
    end

    if (!item.write &&
        matches_reg(item, cfg.ral_model.PIOControl.PIO_INTR_STATUS)) begin
      field_value = extract_field(
        register_value,
        cfg.ral_model.PIOControl.PIO_INTR_STATUS.TRANSFER_ERR_STAT);
      if (field_value[0] && !pio_transfer_error_assert_seen) begin
        emit_pio_transfer_error_irq(2'd1);
        pio_transfer_error_assert_seen = 1'b1;
      end
      else if (!field_value[0] && pio_transfer_error_clear_pending) begin
        emit_pio_transfer_error_irq(2'd2);
        pio_transfer_error_clear_pending = 1'b0;
        pio_transfer_error_assert_seen = 1'b0;
      end
      return;
    end

    if (item.write &&
        matches_reg(item, cfg.ral_model.I3CBase.RESET_CONTROL)) begin
      reset_value = extract_field(
        register_value,
        cfg.ral_model.I3CBase.RESET_CONTROL.IBI_QUEUE_RST);
      if (reset_value[0]) begin
        cfg.ibi_controller_flushed_events += expected_q.size();
        expected_q.delete();
        actual_q.delete();
      end
    end
  endfunction

  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    // The unmatched-queue nets and the event-count rules below observe the same
    // transactions, so in negative mode they are mutually exclusive: any event
    // that lands there is by definition unmatched, and reporting it twice
    // inflates mismatch_count and the triage log. The event-count rules are the
    // more specific report, so they own negative mode.
    if (!cfg.ibi_expect_zero_events) begin
      if (expected_q.size() != 0)
        mismatch("unmatched expected",
                 $sformatf("%0d expected Controller IBI transaction(s) unmatched",
                           expected_q.size()));
      if (actual_q.size() != 0)
        mismatch("unmatched actual",
                 $sformatf("%0d actual Controller IBI transaction(s) unmatched",
                           actual_q.size()));
    end
    // Negative scenarios invert the "zero events means nothing was checked"
    // rule: zero completed IBIs is the requirement, and any event is the
    // failure. Guarded so tests that do not set the flag are unaffected.
    if (cfg.ibi_expect_zero_events) begin
      if (cfg.ibi_controller_actual_events != 0)
        mismatch("unexpected actual",
                 $sformatf("%0d Controller HCI IBI event(s) observed in a scenario that must complete none",
                           cfg.ibi_controller_actual_events));
      if (cfg.ibi_controller_expected_events != 0)
        mismatch("unexpected expected",
                 $sformatf("%0d Controller IBI expected transaction(s) predicted in a scenario that must complete none",
                           cfg.ibi_controller_expected_events));
    end
    else begin
      if (cfg.ibi_controller_expected_events == 0)
        mismatch("missing expected",
                 "No Controller IBI expected transaction was produced");
      if ((cfg.ibi_controller_actual_events +
           cfg.ibi_controller_flushed_events) == 0)
        mismatch("missing actual",
                 "No Controller HCI IBI transaction was observed");
      if (cfg.ibi_controller_expected_events !=
          (cfg.ibi_controller_actual_events +
           cfg.ibi_controller_flushed_events))
        mismatch("event accounting",
                 $sformatf("expected=%0d actual=%0d flushed=%0d",
                           cfg.ibi_controller_expected_events,
                           cfg.ibi_controller_actual_events,
                           cfg.ibi_controller_flushed_events));
    end
    // When the vseq counts launched cases, flag any that never completed on
    // the bus (e.g. RTL A.3 wedges the 2nd+ IBI in a RUN_ALL diagnostic).
    // Guarded so tests that do not set the counter are unaffected.
    if ((cfg.ibi_controller_attempt_cases != 0) &&
        (cfg.ibi_sb_completion_count < cfg.ibi_controller_attempt_cases))
      mismatch("incomplete cases",
               $sformatf("%0d of %0d launched IBI case(s) never completed on the bus (RTL A.3)",
                         cfg.ibi_controller_attempt_cases -
                           cfg.ibi_sb_completion_count,
                         cfg.ibi_controller_attempt_cases));
    if (mismatch_count != 0)
      `uvm_error("IBI_CTRL_SB_SUMMARY",
                 $sformatf("Controller IBI scoreboard mismatches=%0d",
                           mismatch_count))
  endfunction

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("IBI_CTRL_SB_SUMMARY",
              "-------------------------------------------------",
              UVM_LOW)
    `uvm_info("IBI_CTRL_SB_SUMMARY",
              " CONTROLLER IBI SCOREBOARD SUMMARY",
              UVM_LOW)
    `uvm_info("IBI_CTRL_SB_SUMMARY",
              $sformatf(" Expected events : %0d",
                        cfg.ibi_controller_expected_events),
              UVM_LOW)
    `uvm_info("IBI_CTRL_SB_SUMMARY",
              $sformatf(" Actual events   : %0d",
                        cfg.ibi_controller_actual_events),
              UVM_LOW)
    `uvm_info("IBI_CTRL_SB_SUMMARY",
              $sformatf(" Flushed events  : %0d",
                        cfg.ibi_controller_flushed_events),
              UVM_LOW)
    `uvm_info("IBI_CTRL_SB_SUMMARY",
              $sformatf(" Completions     : %0d",
                        cfg.ibi_sb_completion_count),
              UVM_LOW)
    if (cfg.ibi_controller_attempt_cases != 0) begin
      `uvm_info("IBI_CTRL_SB_SUMMARY",
                $sformatf(" Cases launched  : %0d",
                          cfg.ibi_controller_attempt_cases),
                UVM_LOW)
      `uvm_info("IBI_CTRL_SB_SUMMARY",
                $sformatf(" Cases incomplete: %0d",
                          (cfg.ibi_sb_completion_count >=
                             cfg.ibi_controller_attempt_cases) ? 0 :
                            (cfg.ibi_controller_attempt_cases -
                               cfg.ibi_sb_completion_count)),
                UVM_LOW)
    end
    `uvm_info("IBI_CTRL_SB_SUMMARY",
              $sformatf(" Field matches   : %0d", match_count),
              UVM_LOW)
    `uvm_info("IBI_CTRL_SB_SUMMARY",
              $sformatf(" Mismatches      : %0d", mismatch_count),
              UVM_LOW)
    if (mismatch_count == 0)
      `uvm_info("IBI_CTRL_SB_SUMMARY",
                " PASSED: 0 mismatches", UVM_LOW)
    else
      `uvm_error("IBI_CTRL_SB_SUMMARY",
                 $sformatf(" FAILED: %0d mismatch(es)",
                           mismatch_count))
    `uvm_info("IBI_CTRL_SB_SUMMARY",
              "-------------------------------------------------",
              UVM_LOW)
  endfunction
endclass : smc_i3c_ibi_controller_scoreboard

`endif // SMC_I3C_IBI_CONTROLLER_SCOREBOARD_SV
