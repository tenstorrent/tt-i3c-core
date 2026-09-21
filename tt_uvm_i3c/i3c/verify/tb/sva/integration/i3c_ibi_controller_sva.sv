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
// File        : i3c_ibi_controller_sva.sv
// Description : Assertions and cover properties for I3C IBI controller.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-29
//
// *****************************************************************************

module i3c_ibi_controller_sva (
    input logic clk,
    input logic rst_n,
    input logic enable,
    input logic suppress,
    input logic scl,
    input logic sda,
    input logic [6:0] target_addr,
    input logic expected_ack
);
  logic in_frame;
  logic [3:0] bit_count;
  logic [7:0] header;
  logic sda_at_scl_rise;
  logic scl_sample_pulse = 1'b0;
  logic stop_check_pulse = 1'b0;
  logic stop_was_in_frame;
  logic start_epoch;
  logic sampled_start_epoch;

  // Filter SDA transitions that coincide with a falling SCL edge. Sampling
  // SCL in the preponed region misclassifies those data transitions as START
  // or STOP even though SCL is low after the zero-delay signal updates settle.
  always @(posedge sda or negedge sda or negedge rst_n) begin
    if (!rst_n) begin
      in_frame <= 1'b0;
      stop_check_pulse <= 1'b0;
      stop_was_in_frame <= 1'b0;
      start_epoch <= 1'b0;
    end else begin
      #1ps;
      if (enable && (scl === 1'b1)) begin
        if (sda === 1'b0) begin
          in_frame <= 1'b1;
          // Mark every qualified START/repeated-START explicitly. The timing
          // tests suppress IBI-specific properties during a preceding private
          // transfer, so frame state must still be re-armed from the new START
          // rather than inferred from the previous SCL sample history.
          start_epoch <= ~start_epoch;
        end else begin
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
    if (!rst_n) begin
      scl_sample_pulse <= 1'b0;
      sda_at_scl_rise <= 1'b1;
    end else begin
      // Preserve the value present at the protocol sampling edge. In the IBI
      // address-to-ACK handoff the Controller may assert SDA immediately
      // after the RnW edge; sampling SDA after the glitch-filter delay would
      // then mistake that ACK value for the final header bit.
      sda_at_scl_rise <= sda;
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
      bit_count <= '0;
      header <= '0;
      sampled_start_epoch <= 1'b0;
    end else if (!enable || !in_frame) begin
      bit_count <= '0;
      header <= '0;
      sampled_start_epoch <= start_epoch;
    end else begin
      if (sampled_start_epoch != start_epoch) begin
        sampled_start_epoch <= start_epoch;
        header <= {7'b0, sda_at_scl_rise};
        bit_count <= 1;
      end else if (bit_count < 8) begin
        header <= {header[6:0], sda_at_scl_rise};
        bit_count <= bit_count + 1'b1;
      end else if (bit_count == 8) begin
        bit_count <= bit_count + 1'b1;
      end
    end
  end

  ap_ibi_header: assert property (@(posedge scl_sample_pulse)
    disable iff (!rst_n || !enable || suppress)
    in_frame && (bit_count == 8) |-> (header == {target_addr, 1'b1}))
    else $error("SVA: ap_ibi_header header=0x%02h expected=0x%02h DA=0x%02h bit_count=%0d start_epoch=%0b sampled_epoch=%0b",
                header, {target_addr, 1'b1}, target_addr, bit_count,
                start_epoch, sampled_start_epoch);

  ap_controller_response: assert property (@(posedge scl_sample_pulse)
    disable iff (!rst_n || !enable || suppress)
    in_frame && (bit_count == 8) |->
      (sda == (expected_ack ? 1'b0 : 1'b1)))
    else $error("SVA: ap_controller_response");

  ap_controller_stop_after_response: assert property (@(posedge stop_check_pulse)
    disable iff (!rst_n || !enable || suppress)
    stop_was_in_frame |-> (bit_count >= 9))
    else $error("SVA: ap_controller_stop_after_response");

  cp_ibi_address_ack: cover property (@(posedge scl_sample_pulse)
    disable iff (!rst_n || !enable || suppress)
    in_frame && (bit_count == 8) &&
    (header == {target_addr, 1'b1}) && (sda == 1'b0));

  cp_ibi_address_nack: cover property (@(posedge scl_sample_pulse)
    disable iff (!rst_n || !enable || suppress)
    in_frame && (bit_count == 8) &&
    (header == {target_addr, 1'b1}) && (sda == 1'b1));
endmodule : i3c_ibi_controller_sva
