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
// File        : i3c_ibi_protocol_sva.sv
// Description : Transaction-level I3C IBI protocol assertions.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-06
//
// *****************************************************************************

module i3c_ibi_protocol_sva #(
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
    input logic [1:0] queue_state,
    input logic [2:0] queue_status_source,
    input logic [1:0] queue_irq_state,
    input logic queue_role,
    input logic queue_irq_enabled,

    input logic [63:0] arbitration_seq,
    input logic [3:0] requester_active,
    input logic [3:0] requester_winner,
    input logic [3:0] requester_released,

    input logic [63:0] recovery_seq,
    input logic recovery_role,
    input logic [2:0] recovery_cause,
    input logic [1:0] recovery_result,
    input logic recovery_trigger_seen,
    input logic recovery_queue_empty,
    input logic recovery_irq_low,
    input logic recovery_bus_idle,
    input logic recovery_followup_expected,
    input logic recovery_forward_progress,

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
  localparam logic [1:0] QUEUE_FULL = 2'd2;
  localparam logic [2:0] STATUS_SOURCE_ERROR = 3'd3;
  localparam logic [2:0] STATUS_SOURCE_PENDING = 3'd4;
  localparam logic [1:0] IRQ_ASSERTED = 2'd1;
  localparam logic [1:0] IRQ_W1C_CLEARED = 2'd2;
  localparam logic [2:0] MDB_GROUP_PENDING_READ = 3'b101;
  localparam logic [2:0] ERROR_RESET_FLUSH = 3'd1;
  localparam logic [1:0] RECOVERY_RECOVERED = 2'd1;

  logic [63:0] previous_attempt_seq;
  logic [63:0] previous_completion_seq;
  logic [63:0] previous_queue_seq;
  logic [63:0] previous_recovery_seq;
  logic [63:0] previous_arbitration_seq;
  // The UVM probe may increment a sequence counter in the same simulation
  // time slot as posedge clk.  A combinational comparison against the sampled
  // counter then produces only a delta-cycle pulse, after assertion sampling.
  // Register each comparison so every event remains visible for a full cycle.
  logic attempt_event;
  logic completion_event;
  logic queue_event;
  logic recovery_event;
  logic arbitration_event;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      previous_attempt_seq <= attempt_seq;
      previous_completion_seq <= completion_seq;
      previous_queue_seq <= queue_seq;
      previous_recovery_seq <= recovery_seq;
      previous_arbitration_seq <= arbitration_seq;
      attempt_event <= 1'b0;
      completion_event <= 1'b0;
      queue_event <= 1'b0;
      recovery_event <= 1'b0;
      arbitration_event <= 1'b0;
    end else begin
      attempt_event <= attempt_seq != previous_attempt_seq;
      completion_event <= completion_seq != previous_completion_seq;
      queue_event <= queue_seq != previous_queue_seq;
      recovery_event <= recovery_seq != previous_recovery_seq;
      arbitration_event <= arbitration_seq != previous_arbitration_seq;
      previous_attempt_seq <= attempt_seq;
      previous_completion_seq <= completion_seq;
      previous_queue_seq <= queue_seq;
      previous_recovery_seq <= recovery_seq;
      previous_arbitration_seq <= arbitration_seq;
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

  // AFTER_TRANSFER is emitted only by a sequence that observed a completed
  // normal transfer before the IBI attempt. The request may become pending
  // while that transfer is active, but its ATTEMPT must not be published until
  // the normal transfer has released the bus. This applies to both DUT roles.
  ap_ibi_after_transfer_starts_after_normal: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    attempt_event && (attempt_bus_state == BUS_AFTER_TRANSFER) |->
      timing_ibi_pending && !timing_normal_active)
    else $error("SVA: ap_ibi_after_transfer_starts_after_normal");

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
    completion_event && completion_ack && expected_content_valid &&
      (completion_terminal_status == STATUS_SUCCESS) |->
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

  ap_ibi_full_rejects_without_commit: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    queue_event && queue_role && (queue_state == QUEUE_FULL) |->
      !queue_record_write && queue_response_context_valid &&
      !queue_response_ack &&
      (queue_transaction_id == completion_transaction_id) &&
      (completion_terminal_status != STATUS_SUCCESS))
    else $error("SVA: ap_ibi_full_rejects_without_commit");

  ap_ibi_recovery_cleanup: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    recovery_event |->
      (recovery_cause != 0) &&
      (recovery_result == RECOVERY_RECOVERED) &&
      recovery_trigger_seen && recovery_queue_empty &&
      recovery_irq_low && recovery_bus_idle)
    else $error("SVA: ap_ibi_recovery_cleanup");

  ap_ibi_irq_has_status_source: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    queue_event && (queue_irq_state == IRQ_ASSERTED) |->
      !$isunknown(queue_status_source) && (queue_status_source <= 3'd4))
    else $error("SVA: ap_ibi_irq_has_status_source");

  ap_ibi_irq_enable_gating: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    queue_event && queue_role && !queue_irq_enabled |->
      (queue_irq_state != IRQ_ASSERTED))
    else $error("SVA: ap_ibi_irq_enable_gating");

  ap_ibi_loser_releases_sda: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    arbitration_event |->
      ((requester_active & ~requester_winner) &
       ~requester_released) == 4'b0000)
    else $error("SVA: ap_ibi_loser_releases_sda");

  ap_ibi_request_on_bus_idle: assert property (
    @(negedge sda) disable iff (!rst_n || !enable || !timing_check_enable)
    scl === 1'b1 |->
      timing_ibi_pending && timing_ibi_start_allowed &&
      !timing_normal_active)
    else $error("SVA: ap_ibi_request_on_bus_idle");

  // The arbitration probe publishes one bitmap snapshot per round, not one
  // ATTEMPT item per requester.  Check the snapshot directly: exactly one
  // active requester wins the completed contended round.
  ap_ibi_arbitration_single_winner: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    arbitration_event |->
      $onehot(requester_winner) &&
      ((requester_winner & ~requester_active) == 4'b0000))
    else $error("SVA: ap_ibi_arbitration_single_winner");

  // MDB group 101 is the pending-read notification. The controller surfaces its
  // own classification as the HCI status source, so the bus-side group and the
  // backend classification must agree in both directions.
  ap_ibi_mdb_group_decode: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    completion_event && completion_role && completion_ack &&
      completion_mdb_present |->
      ((completion_mdb[7:5] == MDB_GROUP_PENDING_READ) ==
       (queue_status_source == STATUS_SOURCE_PENDING)))
    else $error("SVA: ap_ibi_mdb_group_decode");

  ap_ibi_pending_read_event_classify: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    completion_event && completion_role && completion_ack &&
      completion_mdb_present &&
      (completion_mdb[7:5] == MDB_GROUP_PENDING_READ) |->
      (queue_transaction_id == completion_transaction_id) &&
      (queue_status_source == STATUS_SOURCE_PENDING))
    else $error("SVA: ap_ibi_pending_read_event_classify");

  // A flush must leave nothing behind: it recovers, and it commits no content.
  // ap_ibi_recovery_cleanup only states that some error was recovered.
  ap_ibi_flush_clears_pending_state: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    recovery_event && (recovery_cause == ERROR_RESET_FLUSH) |->
      (recovery_result == RECOVERY_RECOVERED) &&
      recovery_queue_empty && recovery_irq_low)
    else $error("SVA: ap_ibi_flush_clears_pending_state");

  ap_ibi_cleanup_forward_progress: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    recovery_event && (recovery_result == RECOVERY_RECOVERED) &&
      recovery_followup_expected |-> recovery_forward_progress)
    else $error("SVA: ap_ibi_cleanup_forward_progress");

  cp_ibi_recovery_target: cover property (
    @(posedge clk) disable iff (!rst_n || !enable)
    recovery_event && !recovery_role &&
      (recovery_result == RECOVERY_RECOVERED));

  cp_ibi_recovery_controller: cover property (
    @(posedge clk) disable iff (!rst_n || !enable)
    recovery_event && recovery_role &&
      (recovery_result == RECOVERY_RECOVERED));

  // W1C is a clear, not a re-arm. A snapshot reporting the status bit cleared
  // must not be the snapshot that enqueues a new record, or that record's
  // status source is lost.
  ap_ibi_irq_w1c_clears_status: assert property (
    @(posedge clk) disable iff (!rst_n || !enable)
    queue_event && (queue_irq_state == IRQ_W1C_CLEARED) |->
      !queue_record_write)
    else $error("SVA: ap_ibi_irq_w1c_clears_status");

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

  cp_ibi_target_after_normal_transfer: cover property (
    @(posedge clk) disable iff (!rst_n || !enable)
    attempt_event && !attempt_role &&
      (attempt_bus_state == BUS_AFTER_TRANSFER));

  cp_ibi_controller_after_normal_transfer: cover property (
    @(posedge clk) disable iff (!rst_n || !enable)
    attempt_event && attempt_role &&
      (attempt_bus_state == BUS_AFTER_TRANSFER));

  cp_ibi_full_reject: cover property (
    @(posedge clk) disable iff (!rst_n || !enable)
    queue_event && queue_role && (queue_state == QUEUE_FULL) &&
      !queue_record_write && !queue_response_ack);

  cp_ibi_pending_read_notification: cover property (
    @(posedge clk) disable iff (!rst_n || !enable)
    completion_event && completion_mdb_present &&
      (completion_mdb[7:5] == 3'b101));

endmodule : i3c_ibi_protocol_sva
