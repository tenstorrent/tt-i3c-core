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
// File        : smc_i3c_boundary_sva.sv
// Description : Assertions and cover properties for I3C boundary.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-28
//
// *****************************************************************************

module smc_i3c_boundary_sva #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 32
) (
    input logic clk,
    input logic rst_n,
    input logic access_allow,
    input logic [ADDR_WIDTH-1:0] awaddr,
    input logic awvalid,
    input logic awready,
    input logic [DATA_WIDTH-1:0] wdata,
    input logic [DATA_WIDTH/8-1:0] wstrb,
    input logic wvalid,
    input logic wready,
    input logic [1:0] bresp,
    input logic bvalid,
    input logic bready,
    input logic [ADDR_WIDTH-1:0] araddr,
    input logic arvalid,
    input logic arready,
    input logic [DATA_WIDTH-1:0] rdata,
    input logic [1:0] rresp,
    input logic rvalid,
    input logic rready
);
    ap_aw_stable: assert property (@(posedge clk) disable iff (!rst_n)
                                   awvalid && !awready
                                   |=> awvalid && $stable(awaddr))
      else $error("SVA: ap_aw_stable");
    ap_w_stable: assert property (@(posedge clk) disable iff (!rst_n)
                                  wvalid && !wready
                                  |=> wvalid && $stable({wdata, wstrb}))
      else $error("SVA: ap_w_stable");
    ap_ar_stable: assert property (@(posedge clk) disable iff (!rst_n)
                                   arvalid && !arready
                                   |=> arvalid && $stable(araddr))
      else $error("SVA: ap_ar_stable");
    ap_b_stable: assert property (@(posedge clk) disable iff (!rst_n)
                                  bvalid && !bready
                                  |=> bvalid && $stable(bresp))
      else $error("SVA: ap_b_stable");
    ap_r_stable: assert property (@(posedge clk) disable iff (!rst_n)
                                  rvalid && !rready
                                  |=> rvalid && $stable({rdata, rresp}))
      else $error("SVA: ap_r_stable");
    ap_denied_write: assert property (@(posedge clk) disable iff (!rst_n)
                                      !access_allow && awvalid && awready
                                      |-> ##[0:32] (bvalid && bresp == 2'b11))
      else $error("SVA: ap_denied_write");
    ap_denied_read: assert property (@(posedge clk) disable iff (!rst_n)
                                     !access_allow && arvalid && arready
                                     |-> ##[0:32] (rvalid && rresp == 2'b11))
      else $error("SVA: ap_denied_read");
endmodule : smc_i3c_boundary_sva
