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
// File        : smc_peripherals_if.sv
// Description : Signal interface between the DUT and UVM environment.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-25
//
// *****************************************************************************

interface smc_peripherals_if
(
    input logic clk,
    input logic rst_n,
    inout wire i3c_scl,
    inout wire i3c_sda
);
    logic dut_present;
    logic smoke_seen_reset_release;
    logic i3c_irq;
    logic i3c_recovery_payload_available;
    logic i3c_recovery_image_activated;
    logic i3c_peripheral_reset;
    logic i3c_escalated_reset;
    logic i3c_scl_oe;
    logic i3c_sda_oe;
    logic i3c_target_sda_drive_low = 1'b0;
    logic i3c_controller_expected_ack = 1'b1;
    logic [6:0] i3c_controller_expected_addr = 7'h5a;

    // Testbench-visible markers for Controller IBI timing-context checks.
    // They describe stimulus intent and the legal IBI-start window; they are
    // not DUT pins and are cleared by the timing-context vseq.
    logic i3c_controller_sva_check_enable = 1'b0;
    logic i3c_timing_normal_active = 1'b0;
    logic i3c_timing_ibi_pending = 1'b0;
    logic i3c_timing_ibi_start_allowed = 1'b0;

    // Normalized, transaction-level SVA probes. UVM analysis subscribers
    // update the snapshot fields first and increment the corresponding
    // sequence counter last. SVA therefore observes one coherent event
    // without depending on private RTL hierarchy.
    longint unsigned i3c_sva_attempt_seq = 0;
    logic i3c_sva_attempt_role = 1'b0;
    logic [1:0] i3c_sva_attempt_addr_class = 2'd3;
    logic [7:0] i3c_sva_attempt_bcr = '0;
    logic i3c_sva_attempt_ibi_enabled = 1'b0;
    int unsigned i3c_sva_attempt_requester_count = 0;
    logic [1:0] i3c_sva_attempt_arb_outcome = 2'd0;
    logic [1:0] i3c_sva_attempt_bus_state = 2'd0;

    longint unsigned i3c_sva_completion_seq = 0;
    longint unsigned i3c_sva_completion_transaction_id = 0;
    logic i3c_sva_completion_role = 1'b0;
    logic i3c_sva_completion_ack = 1'b0;
    int unsigned i3c_sva_completion_retry_count = 0;
    logic [2:0] i3c_sva_completion_terminal_status = 3'd0;
    logic i3c_sva_completion_mdb_present = 1'b0;
    logic [7:0] i3c_sva_completion_mdb = '0;
    int unsigned i3c_sva_completion_payload_len = 0;
    logic i3c_sva_completion_dat_match = 1'b0;
    logic [1:0] i3c_sva_completion_payload_policy = 2'd0;
    logic i3c_sva_completion_ibi_enabled = 1'b0;
    logic [2:0] i3c_sva_completion_error_kind = 3'd0;
    logic [1:0] i3c_sva_completion_recovery_result = 2'd0;
    logic i3c_sva_expected_content_valid = 1'b0;
    logic i3c_sva_expected_mdb_present = 1'b0;
    logic [7:0] i3c_sva_expected_mdb = '0;
    int unsigned i3c_sva_expected_payload_len = 0;

    longint unsigned i3c_sva_queue_seq = 0;
    longint unsigned i3c_sva_queue_transaction_id = 0;
    logic i3c_sva_queue_record_write = 1'b0;
    logic i3c_sva_queue_response_context_valid = 1'b0;
    logic i3c_sva_queue_response_ack = 1'b0;
    logic [1:0] i3c_sva_queue_record_kind = 2'd0;
    logic [1:0] i3c_sva_queue_state = 2'd0;
    logic [2:0] i3c_sva_queue_status_source = 3'd0;
    logic [1:0] i3c_sva_queue_irq_state = 2'd0;

    logic       sanity_start_seen;
    logic       sanity_address_ack_sent;
    logic [7:0] sanity_address_byte;
    logic [7:0] sanity_data_byte;
    logic       sanity_t_bit;
    logic       sanity_stop_seen;
    logic       sanity_transaction_done;
    int unsigned sanity_scl_rise_count;

    assign i3c_sda = i3c_target_sda_drive_low ? 1'b0 : 1'bz;

    task automatic respond_one_byte_private_write(
        output bit       completed,
        output bit [7:0] address_byte,
        output bit [7:0] data_byte,
        output bit       t_bit,
        input int unsigned timeout_cycles = 200_000
    );
        bit responder_done;

        completed = 1'b0;
        address_byte = '0;
        data_byte = '0;
        t_bit = 1'b0;
        responder_done = 1'b0;
        i3c_target_sda_drive_low = 1'b0;
        sanity_start_seen = 1'b0;
        sanity_address_ack_sent = 1'b0;
        sanity_address_byte = '0;
        sanity_data_byte = '0;
        sanity_t_bit = 1'b0;
        sanity_stop_seen = 1'b0;
        sanity_transaction_done = 1'b0;
        sanity_scl_rise_count = 0;

        fork
            begin : responder
                forever begin
                    @(negedge i3c_sda);
                    if (i3c_scl === 1'b1)
                        break;
                end
                sanity_start_seen = 1'b1;

                // The controller emits one SCL handoff edge while leaving the
                // START phase. Address data becomes valid on the following edge.
                @(posedge i3c_scl);

                for (int bit_index = 7; bit_index >= 0; bit_index--) begin
                    @(posedge i3c_scl);
                    sanity_scl_rise_count++;
                    address_byte[bit_index] = i3c_sda;
                end
                sanity_address_byte = address_byte;

                // The address header is open-drain. Pull SDA low for the ACK bit.
                @(negedge i3c_scl);
                i3c_target_sda_drive_low = 1'b1;
                @(posedge i3c_scl);
                sanity_scl_rise_count++;
                sanity_address_ack_sent = 1'b1;
                @(negedge i3c_scl);
                i3c_target_sda_drive_low = 1'b0;

                for (int bit_index = 7; bit_index >= 0; bit_index--) begin
                    @(posedge i3c_scl);
                    sanity_scl_rise_count++;
                    data_byte[bit_index] = i3c_sda;
                end
                sanity_data_byte = data_byte;

                @(posedge i3c_scl);
                sanity_scl_rise_count++;
                t_bit = i3c_sda;
                sanity_t_bit = t_bit;

                forever begin
                    @(posedge i3c_sda);
                    if (i3c_scl === 1'b1)
                        break;
                end
                sanity_stop_seen = 1'b1;
                sanity_transaction_done = 1'b1;
                responder_done = 1'b1;
            end
            begin : responder_timeout
                repeat (timeout_cycles)
                    @(posedge clk);
            end
        join_any
        disable fork;

        i3c_target_sda_drive_low = 1'b0;
        completed = responder_done;
    endtask

    task automatic mark_smoke_seen_reset_release();
        smoke_seen_reset_release = 1'b1;
    endtask
endinterface : smc_peripherals_if
