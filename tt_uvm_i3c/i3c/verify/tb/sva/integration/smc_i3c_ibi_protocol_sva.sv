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
// File        : smc_i3c_ibi_protocol_sva.sv
// Description : Portable transaction-level I3C IBI protocol assertions.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-29
//
// *****************************************************************************

module smc_i3c_ibi_protocol_sva #(
    parameter int unsigned MAX_RETRY_COUNT = 7
) (
    input logic clk,
    input logic rst_n,
    input logic enable,

    input logic [63:0] attempt_seq,
    input logic attempt_role,
    input logic [1:0] attempt_addr_class,
    input logic [7:0] attempt_bcr,
    input logic attempt_ibi_enabled,
    input int unsigned attempt_requester_count,
    input logic [1:0] attempt_arb_outcome,
    input logic [1:0] attempt_bus_state,

    input logic [63:0] completion_seq,
    input logic [63:0] completion_transaction_id,
    input logic completion_role,
    input logic completion_ack,
    input int unsigned completion_retry_count,
    input logic [2:0] completion_terminal_status,
    input logic completion_mdb_present,
    input logic [7:0] completion_mdb,
    input int unsigned completion_payload_len,
    input logic completion_dat_match,
    input logic [1:0] completion_payload_policy,
    input logic completion_ibi_enabled,
    input logic [2:0] completion_error_kind,
    input logic [1:0] completion_recovery_result,
    input logic expected_content_valid,
    input logic expected_mdb_present,
    input logic [7:0] expected_mdb,
    input int unsigned expected_payload_len,

    input logic [63:0] queue_seq,
    input logic [63:0] queue_transaction_id,
    input logic queue_record_write,
    input logic queue_response_context_valid,
    input logic queue_response_ack,
    input logic [1:0] queue_record_kind,
    input logic [1:0] queue_state,
    input logic [2:0] queue_status_source,
    input logic [1:0] queue_irq_state,

    input logic scl,
    input logic sda,
    input logic timing_check_enable,
    input logic timing_normal_active,
    input logic timing_ibi_pending,
    input logic timing_ibi_start_allowed
);
  localparam logic [1:0] ADDR_VALID = 2'd0;
  localparam logic [1:0] ARB_SOLE = 2'd0;
  localparam logic [1:0] ARB_WON = 2'd1;
  localparam logic [1:0] ARB_LOST = 2'd2;
  localparam logic [1:0] BUS_AFTER_TRANSFER = 2'd2;
  localparam logic [1:0] BUS_BUSY = 2'd3;
  localparam logic [2:0] STATUS_SUCCESS = 3'd0;
  localparam logic [1:0] RECOVERY_NA = 2'd0;
  localparam logic [1:0] QUEUE_OVERFLOW = 2'd3;
  localparam logic [2:0] STATUS_SOURCE_ERROR = 3'd3;
  localparam logic [1:0] IRQ_ASSERTED = 2'd1;

  logic [63:0] previous_attempt_seq;
  logic [63:0] previous_completion_seq;
  logic [63:0] previous_queue_seq;
  wire attempt_event = attempt_seq != previous_attempt_seq;
  wire completion_event = completion_seq != previous_completion_seq;
  wire queue_event = queue_seq != previous_queue_seq;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      previous_attempt_seq <= attempt_seq;
      previous_completion_seq <= completion_seq;
      previous_queue_seq <= queue_seq;
    end else begin
      previous_attempt_seq <= attempt_seq;
      previous_completion_seq <= completion_seq;
      previous_queue_seq <= queue_seq;
    end
  end

  ap_ibi_start_only_when_enabled: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    attempt_event && !attempt_role |-> attempt_ibi_enabled)
    else $error("SVA: ap_ibi_start_only_when_enabled");

  ap_ibi_no_request_when_busy: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    attempt_event |-> attempt_bus_state != BUS_BUSY)
    else $error("SVA: ap_ibi_no_request_when_busy");

  ap_ibi_valid_target_only: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    attempt_event && !attempt_role |->
      (attempt_addr_class == ADDR_VALID) && attempt_bcr[1])
    else $error("SVA: ap_ibi_valid_target_only");

  ap_ibi_arbitration_context: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    attempt_event |->
      ((attempt_requester_count == 1) &&
       (attempt_arb_outcome == ARB_SOLE)) ||
      ((attempt_requester_count > 1) &&
       (attempt_arb_outcome inside {ARB_WON, ARB_LOST})))
    else $error("SVA: ap_ibi_arbitration_context");

  ap_ibi_retry_count_bounded: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    completion_event |-> completion_retry_count <= MAX_RETRY_COUNT)
    else $error("SVA: ap_ibi_retry_count_bounded");

  ap_ibi_ack_advances_payload: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    completion_event && completion_ack &&
      (completion_payload_len != 0) |-> completion_mdb_present)
    else $error("SVA: ap_ibi_ack_advances_payload");

  ap_ibi_nack_stops_or_retries: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    completion_event && !completion_ack |->
      !completion_mdb_present &&
      (completion_payload_len == 0) &&
      (completion_terminal_status != STATUS_SUCCESS))
    else $error("SVA: ap_ibi_nack_stops_or_retries");

  ap_ibi_mdb_presence_matches_descriptor: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    completion_event && completion_ack && expected_content_valid |->
      (completion_mdb_present == expected_mdb_present))
    else $error("SVA: ap_ibi_mdb_presence_matches_descriptor");

  ap_ibi_payload_length_matches_descriptor: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    completion_event && completion_ack && expected_content_valid |->
      (completion_payload_len == expected_payload_len))
    else $error("SVA: ap_ibi_payload_length_matches_descriptor");

  ap_ibi_mdb_value_matches_descriptor: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    completion_event && completion_ack && expected_content_valid &&
      expected_mdb_present |->
      completion_mdb_present && (completion_mdb == expected_mdb))
    else $error("SVA: ap_ibi_mdb_value_matches_descriptor");

  ap_ibi_controller_policy: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    completion_event && completion_role &&
      (!completion_dat_match || (completion_payload_policy == 0) ||
       !completion_ibi_enabled) |-> !completion_ack)
    else $error("SVA: ap_ibi_controller_policy");

  ap_ibi_accepted_updates_fifo: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    completion_event && completion_role && completion_ack |->
      (queue_transaction_id == completion_transaction_id) &&
      queue_record_write && queue_response_context_valid &&
      queue_response_ack)
    else $error("SVA: ap_ibi_accepted_updates_fifo");

  ap_ibi_rejected_no_payload_commit: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    queue_event && queue_record_write |->
      queue_response_context_valid && queue_response_ack)
    else $error("SVA: ap_ibi_rejected_no_payload_commit");

  ap_ibi_overflow_reports_abort: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    queue_event && (queue_state == QUEUE_OVERFLOW) |->
      (queue_status_source == STATUS_SOURCE_ERROR) &&
      ((queue_transaction_id != completion_transaction_id) ||
       (completion_terminal_status != STATUS_SUCCESS)))
    else $error("SVA: ap_ibi_overflow_reports_abort");

  ap_ibi_recovery_cleanup: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    completion_event && (completion_error_kind != 0) |->
      (completion_recovery_result != RECOVERY_NA) &&
      (completion_terminal_status != STATUS_SUCCESS))
    else $error("SVA: ap_ibi_recovery_cleanup");

  ap_ibi_irq_has_status_source: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    queue_event && (queue_irq_state == IRQ_ASSERTED) |->
      !$isunknown(queue_status_source) && (queue_status_source <= 3'd4))
    else $error("SVA: ap_ibi_irq_has_status_source");

  ap_ibi_request_on_bus_idle: assert property (
    @(negedge sda) disable iff (!rst_n || !enable || !timing_check_enable)
    scl === 1'b1 |->
      timing_ibi_pending && timing_ibi_start_allowed &&
      !timing_normal_active)
    else $error("SVA: ap_ibi_request_on_bus_idle");

  cp_ibi_without_mdb: cover property (
    @(posedge clk) disable iff (!rst_n || !enable)
    completion_event && completion_ack && !completion_mdb_present);

  cp_ibi_with_mdb: cover property (
    @(posedge clk) disable iff (!rst_n || !enable)
    completion_event && completion_ack && completion_mdb_present);

  cp_ibi_with_payload: cover property (
    @(posedge clk) disable iff (!rst_n || !enable)
    completion_event && completion_ack && (completion_payload_len != 0));

  cp_ibi_multi_target_arbitration: cover property (
    @(posedge clk) disable iff (!rst_n || !enable)
    attempt_event && (attempt_requester_count > 1) &&
      (attempt_arb_outcome == ARB_WON));

  cp_ibi_after_normal_transfer: cover property (
    @(posedge clk) disable iff (!rst_n || !enable)
    attempt_event && (attempt_bus_state == BUS_AFTER_TRANSFER));

  cp_ibi_overflow_abort: cover property (
    @(posedge clk) disable iff (!rst_n || !enable)
    queue_event && (queue_state == QUEUE_OVERFLOW) &&
      (queue_status_source == STATUS_SOURCE_ERROR));

  cp_ibi_pending_read_notification: cover property (
    @(posedge clk) disable iff (!rst_n || !enable)
    completion_event && completion_mdb_present &&
      (completion_mdb[7:5] == 3'b101));

  // Keep queue_record_kind visible to coverage and lint even when no overflow
  // scenario has been enabled in the current regression.
  cp_ibi_error_record: cover property (
    @(posedge clk) disable iff (!rst_n || !enable)
    queue_event && (queue_record_kind == 2'd2));
endmodule : smc_i3c_ibi_protocol_sva
