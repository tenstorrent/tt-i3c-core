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
// File        : i3c_ibi_bus_sva.sv
// Description : Assertions and cover properties for I3C IBI bus.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-28
//
// *****************************************************************************

module i3c_ibi_bus_sva #(
    parameter int unsigned FRAME_TIMEOUT_CYCLES = 200_000
) (
    input logic clk,
    input logic rst_n,
    input logic enable,
    input logic scl,
    input logic sda,
    input logic dut_sda_drive_enable,
    input logic dut_sda_value,
    input logic irq
);
  logic in_frame;
  int unsigned frame_age_cycles;

  // START and STOP are the only SDA transitions allowed while SCL is high.
  // Tracking them asynchronously avoids depending on the unrelated host clock.
  always @(posedge sda or negedge sda or negedge rst_n) begin
    if (!rst_n)
      in_frame <= 1'b0;
    else if (enable && (scl === 1'b1))
      in_frame <= (sda === 1'b0);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || !enable || !in_frame)
      frame_age_cycles <= 0;
    else if (frame_age_cycles < FRAME_TIMEOUT_CYCLES)
      frame_age_cycles <= frame_age_cycles + 1;
  end

  ap_bus_known: assert property (@(posedge clk) disable iff (!rst_n)
    enable |-> !$isunknown({scl, sda}))
    else $error("SVA: ap_bus_known");

  ap_dut_drive_known: assert property (@(posedge clk) disable iff (!rst_n)
    enable && dut_sda_drive_enable |-> !$isunknown(dut_sda_value))
    else $error("SVA: ap_dut_drive_known");

  // Check the bound throughout an active frame. The previous endpoint-only
  // implication had no success attempts for every normal frame that ended
  // before the timeout, making assertion coverage vacuous despite correct
  // traffic.
  ap_ibi_frame_bounded: assert property (@(posedge clk) disable iff (!rst_n)
    enable && in_frame |-> frame_age_cycles < FRAME_TIMEOUT_CYCLES)
    else $error("SVA: ap_ibi_frame_bounded");

  ap_irq_known: assert property (@(posedge clk) disable iff (!rst_n)
    enable |-> !$isunknown(irq))
    else $error("SVA: ap_irq_known");

  ap_reset_releases_sda: assert property (@(posedge clk)
    !rst_n |=> !dut_sda_drive_enable)
    else $error("SVA: ap_reset_releases_sda");

  cp_ibi_frame_complete: cover property (@(posedge clk)
    disable iff (!rst_n || !enable)
    $fell(in_frame));

  cp_ibi_irq_asserted: cover property (@(posedge clk)
    disable iff (!rst_n || !enable)
    $rose(irq));
endmodule : i3c_ibi_bus_sva
