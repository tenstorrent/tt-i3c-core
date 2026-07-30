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
// File        : smc_i3c_ibi_controller_sva.sv
// Description : Assertions and cover properties for I3C IBI controller.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-29
//
// *****************************************************************************

module smc_i3c_ibi_controller_sva (
    input logic clk,
    input logic rst_n,
    input logic enable,
    input logic scl,
    input logic sda,
    input logic [6:0] target_addr,
    input logic expected_ack
);
  logic in_frame;
  logic frame_sampled;
  logic [3:0] bit_count;
  logic [7:0] header;
  logic scl_sample_pulse = 1'b0;
  logic stop_check_pulse = 1'b0;
  logic stop_was_in_frame;

  // Filter SDA transitions that coincide with a falling SCL edge. Sampling
  // SCL in the preponed region misclassifies those data transitions as START
  // or STOP even though SCL is low after the zero-delay signal updates settle.
  always @(posedge sda or negedge sda or negedge rst_n) begin
    if (!rst_n) begin
      in_frame <= 1'b0;
      stop_check_pulse <= 1'b0;
      stop_was_in_frame <= 1'b0;
    end else begin
      #1ps;
      if (enable && (scl === 1'b1)) begin
        if (sda === 1'b0)
          in_frame <= 1'b1;
        else begin
          stop_was_in_frame <= in_frame;
          in_frame <= 1'b0;
          #1ps;
          stop_check_pulse <= 1'b1;
          #1ps;
          stop_check_pulse <= 1'b0;
        end
      end
    end
  end

  // Reject zero-width SCL transitions produced while the Controller changes
  // transfer state. Only a level that remains high for one precision step is
  // a protocol sampling edge.
  always @(posedge scl or negedge rst_n) begin
    if (!rst_n)
      scl_sample_pulse <= 1'b0;
    else begin
      #1ps;
      if (scl === 1'b1) begin
        scl_sample_pulse <= 1'b1;
        #1ps;
        scl_sample_pulse <= 1'b0;
      end
    end
  end

  always @(posedge scl_sample_pulse or negedge rst_n) begin
    if (!rst_n) begin
      frame_sampled <= 1'b0;
      bit_count <= '0;
      header <= '0;
    end else if (!enable || !in_frame) begin
      frame_sampled <= 1'b0;
      bit_count <= '0;
      header <= '0;
    end else begin
      frame_sampled <= 1'b1;
      if (!frame_sampled) begin
        header <= {7'b0, sda};
        bit_count <= 1;
      end else if (bit_count < 8) begin
        header <= {header[6:0], sda};
        bit_count <= bit_count + 1'b1;
      end else if (bit_count == 8) begin
        bit_count <= bit_count + 1'b1;
      end
    end
  end

  ap_ibi_header: assert property (@(posedge scl_sample_pulse)
    disable iff (!rst_n || !enable)
    in_frame && (bit_count == 8) |-> (header == {target_addr, 1'b1}))
    else $error("SVA: ap_ibi_header");

  ap_controller_response: assert property (@(posedge scl_sample_pulse)
    disable iff (!rst_n || !enable)
    in_frame && (bit_count == 8) |->
      (sda == (expected_ack ? 1'b0 : 1'b1)))
    else $error("SVA: ap_controller_response");

  ap_controller_stop_after_response: assert property (@(posedge stop_check_pulse)
    disable iff (!rst_n || !enable)
    stop_was_in_frame |-> (bit_count >= 9))
    else $error("SVA: ap_controller_stop_after_response");

  cp_ibi_address_ack: cover property (@(posedge scl_sample_pulse)
    disable iff (!rst_n || !enable)
    in_frame && (bit_count == 8) &&
    (header == {target_addr, 1'b1}) && (sda == 1'b0));

  cp_ibi_address_nack: cover property (@(posedge scl_sample_pulse)
    disable iff (!rst_n || !enable)
    in_frame && (bit_count == 8) &&
    (header == {target_addr, 1'b1}) && (sda == 1'b1));
endmodule : smc_i3c_ibi_controller_sva
