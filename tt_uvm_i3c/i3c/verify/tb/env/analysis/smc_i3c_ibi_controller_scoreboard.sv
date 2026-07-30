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
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-25
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_CONTROLLER_SCOREBOARD_SV
`define SMC_I3C_IBI_CONTROLLER_SCOREBOARD_SV

`uvm_analysis_imp_decl(_ibi_ctrl_sb_expected)
`uvm_analysis_imp_decl(_ibi_ctrl_sb_actual)

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
  uvm_analysis_port #(smc_i3c_ibi_item) coverage_port;

  smc_peripherals_env_cfg cfg;
  protected smc_i3c_ibi_expected_item expected_q[$];
  protected smc_i3c_ibi_controller_actual_item actual_q[$];
  int unsigned match_count;
  int unsigned mismatch_count;

  function new(string name = "smc_i3c_ibi_controller_scoreboard",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    expected_export = new("expected_export", this);
    actual_export = new("actual_export", this);
    coverage_port = new("coverage_port", this);
    if (cfg == null)
      `uvm_fatal("IBI_CTRL_SB_CFG",
                 "Controller scoreboard requires environment config")
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

  protected function void compare_bytes(
      string source,
      smc_i3c_ibi_expected_item expected,
      byte unsigned actual[$]);
    int unsigned expected_size;
    bit failed;

    expected_size = expected.expected_ack ?
      ((expected.mdb_present ? 1 : 0) + expected.payload_len) : 0;
    failed = actual.size() != expected_size;
    if (!failed && expected.mdb_present &&
        (actual[0] !== expected.mdb))
      failed = 1'b1;
    if (!failed) begin
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
    item.queue_record_write = 1'b1;
    item.response_context_valid = 1'b1;
    item.ack = actual.ack;
    // The Controller HCI exposes the queued record, but no direct occupancy
    // CSR. For this single-IBI scenario, enqueue occupancy is the observed
    // status descriptor plus its observed payload DWORDs.
    item.fifo_level = 1 + ((actual.data_length + 3) / 4);
    item.record_kind = (actual.hci_data.size() != 0) ? 2'd1 : 2'd0;
    item.queue_state = 2'd0;
    item.status_source = 3'd0;
    item.irq_state = actual.irq_seen ? 2'd1 : 2'd0;
    item.threshold_relation_valid = 1'b1;
    item.threshold_reached = actual.irq_seen;
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
    if (actual.ibi_id !== {1'b0, expected.target_addr})
      mismatch("HCI IBI_ID",
               $sformatf("expected=0x%02h actual=0x%02h",
                         {1'b0, expected.target_addr}, actual.ibi_id));
    else
      match("HCI IBI_ID");
    if (actual.data_length != expected_bytes)
      mismatch("HCI DATA_LENGTH",
               $sformatf("expected=%0d actual=%0d",
                         expected_bytes, actual.data_length));
    else
      match("HCI DATA_LENGTH");
    if (actual.status_type !== 3'b000)
      mismatch("HCI STATUS_TYPE",
               $sformatf("expected RegularIBI(0) actual=0x%0h",
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
    if (!actual.irq_seen)
      mismatch("IRQ", "IBI record was not accompanied by IRQ");
    else
      match("IRQ");

    compare_bytes("HCI FIFO", expected, actual.hci_data);
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

  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (expected_q.size() != 0)
      mismatch("unmatched expected",
               $sformatf("%0d expected Controller IBI transaction(s) unmatched",
                         expected_q.size()));
    if (actual_q.size() != 0)
      mismatch("unmatched actual",
               $sformatf("%0d actual Controller IBI transaction(s) unmatched",
                         actual_q.size()));
    if (cfg.ibi_controller_expected_events == 0)
      mismatch("missing expected",
               "No Controller IBI expected transaction was produced");
    if (cfg.ibi_controller_actual_events == 0)
      mismatch("missing actual",
               "No Controller HCI IBI transaction was observed");
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
