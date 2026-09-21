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
// File        : i3c_ibi_target_sva.sv
// Description : Assertions and cover properties for I3C IBI target.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-12
//
// *****************************************************************************

module i3c_ibi_target_sva (
    input logic clk,
    input logic rst_n,
    input logic enable,
    input logic scl,
    input logic sda,
    input logic dut_sda_drive_enable,
    input logic dut_sda_value,
    input logic [6:0] target_addr
);
  logic in_frame;
  logic frame_sampled;
  logic response_seen;
  logic nack_active;
  logic [3:0] bit_count;
  logic [7:0] header;
  logic scl_sample_pulse = 1'b0;
  int unsigned target_attempt;
  int unsigned sampled_attempt;

  // Qualify START with DUT ownership so Controller-originated setup traffic is
  // not misclassified as a Target IBI.
  always @(posedge sda or negedge sda or negedge rst_n) begin
    if (!rst_n) begin
      in_frame <= 1'b0;
      target_attempt <= 0;
    end else if (enable && (scl === 1'b1)) begin
      if ((sda === 1'b0) && (dut_sda_drive_enable === 1'b1) &&
          (dut_sda_value === 1'b0)) begin
        in_frame <= 1'b1;
        target_attempt <= target_attempt + 1;
      end else if (sda === 1'b1)
        in_frame <= 1'b0;
    end
  end

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
      response_seen <= 1'b0;
      nack_active <= 1'b0;
      bit_count <= '0;
      header <= '0;
      sampled_attempt <= 0;
    end else if (!enable || !in_frame) begin
      frame_sampled <= 1'b0;
      response_seen <= 1'b0;
      nack_active <= 1'b0;
      bit_count <= '0;
      header <= '0;
      sampled_attempt <= target_attempt;
    end else begin
      if (!frame_sampled || (sampled_attempt != target_attempt)) begin
        frame_sampled <= 1'b1;
        response_seen <= 1'b0;
        nack_active <= 1'b0;
        sampled_attempt <= target_attempt;
        header <= {7'b0, sda};
        bit_count <= 1;
      end else if (bit_count < 8) begin
        header <= {header[6:0], sda};
        bit_count <= bit_count + 1'b1;
      end else if (bit_count == 8) begin
        response_seen <= 1'b1;
        nack_active <= (sda === 1'b1);
        bit_count <= bit_count + 1'b1;
      end
    end
  end

  // A different resolved header is legal when another Target has a lower
  // dynamic address. In that case this DUT lost arbitration; it must release
  // SDA and must not be checked as the owner of the rest of that frame.
  ap_target_releases_after_arbitration_loss: assert property (
    @(posedge scl_sample_pulse) disable iff (!rst_n || !enable)
    in_frame && (bit_count == 8) &&
    (header != {target_addr, 1'b1}) |-> !dut_sda_drive_enable)
    else $error("SVA: ap_target_releases_after_arbitration_loss");

  ap_target_header: assert property (@(posedge scl_sample_pulse)
    disable iff (!rst_n || !enable)
    in_frame && (bit_count == 8) |->
      (header <= {target_addr, 1'b1}))
    else $error("SVA: ap_target_header");

  ap_target_releases_response_bit: assert property (
    @(posedge scl_sample_pulse) disable iff (!rst_n || !enable)
    in_frame && (bit_count == 8) &&
    (header == {target_addr, 1'b1}) |-> !dut_sda_drive_enable)
    else $error("SVA: ap_target_releases_response_bit");

  ap_target_no_data_after_nack: assert property (
    @(posedge scl_sample_pulse) disable iff (!rst_n || !enable)
    in_frame && (header == {target_addr, 1'b1}) &&
    nack_active |-> !dut_sda_drive_enable)
    else $error("SVA: ap_target_no_data_after_nack");

  ap_target_stop_after_response: assert property (@(posedge sda)
    disable iff (!rst_n || !enable)
    (scl === 1'b1) && in_frame &&
    (bit_count >= 8) && (header == {target_addr, 1'b1}) |-> response_seen)
    else $error("SVA: ap_target_stop_after_response");

  cp_target_ibi_ack: cover property (@(posedge scl_sample_pulse)
    disable iff (!rst_n || !enable)
    in_frame && (bit_count == 8) &&
    (header == {target_addr, 1'b1}) && (sda == 1'b0));

  cp_target_ibi_nack: cover property (@(posedge scl_sample_pulse)
    disable iff (!rst_n || !enable)
    in_frame && (bit_count == 8) &&
    (header == {target_addr, 1'b1}) && (sda == 1'b1));
endmodule : i3c_ibi_target_sva
