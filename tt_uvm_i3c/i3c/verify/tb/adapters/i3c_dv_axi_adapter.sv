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
// File        : i3c_dv_axi_adapter.sv
// Description : Generic AXI4-Lite to native AXI adapter for the I3C DV boundary.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-09-08
//
// *****************************************************************************

`timescale 1ns/1ps

module i3c_dv_axi_adapter #(
    parameter int unsigned HOST_ADDR_WIDTH = 32,
    parameter int unsigned HOST_DATA_WIDTH = 32,
    parameter int unsigned CORE_ADDR_WIDTH = 12,
    parameter int unsigned CORE_DATA_WIDTH = 32,
    parameter int unsigned CORE_USER_WIDTH = 32,
    parameter int unsigned CORE_ID_WIDTH   = 1
) (
    input  logic                         clk_i,
    input  logic                         rst_ni,

    input  logic [HOST_ADDR_WIDTH-1:0]   s_awaddr_i,
    input  logic                         s_awvalid_i,
    output logic                         s_awready_o,
    input  logic [HOST_DATA_WIDTH-1:0]   s_wdata_i,
    input  logic [HOST_DATA_WIDTH/8-1:0] s_wstrb_i,
    input  logic                         s_wvalid_i,
    output logic                         s_wready_o,
    output logic [1:0]                   s_bresp_o,
    output logic                         s_bvalid_o,
    input  logic                         s_bready_i,

    input  logic [HOST_ADDR_WIDTH-1:0]   s_araddr_i,
    input  logic                         s_arvalid_i,
    output logic                         s_arready_o,
    output logic [HOST_DATA_WIDTH-1:0]   s_rdata_o,
    output logic [1:0]                   s_rresp_o,
    output logic                         s_rvalid_o,
    input  logic                         s_rready_i,

    output logic [CORE_ADDR_WIDTH-1:0]   m_awaddr_o,
    output logic [1:0]                   m_awburst_o,
    output logic [2:0]                   m_awsize_o,
    output logic [7:0]                   m_awlen_o,
    output logic [CORE_USER_WIDTH-1:0]   m_awuser_o,
    output logic [CORE_ID_WIDTH-1:0]     m_awid_o,
    output logic                         m_awlock_o,
    output logic                         m_awvalid_o,
    input  logic                         m_awready_i,
    output logic [CORE_DATA_WIDTH-1:0]   m_wdata_o,
    output logic [CORE_DATA_WIDTH/8-1:0] m_wstrb_o,
    output logic [CORE_USER_WIDTH-1:0]   m_wuser_o,
    output logic                         m_wlast_o,
    output logic                         m_wvalid_o,
    input  logic                         m_wready_i,
    input  logic [1:0]                   m_bresp_i,
    input  logic [CORE_ID_WIDTH-1:0]     m_bid_i,
    input  logic [CORE_USER_WIDTH-1:0]   m_buser_i,
    input  logic                         m_bvalid_i,
    output logic                         m_bready_o,

    output logic [CORE_ADDR_WIDTH-1:0]   m_araddr_o,
    output logic [1:0]                   m_arburst_o,
    output logic [2:0]                   m_arsize_o,
    output logic [7:0]                   m_arlen_o,
    output logic [CORE_USER_WIDTH-1:0]   m_aruser_o,
    output logic [CORE_ID_WIDTH-1:0]     m_arid_o,
    output logic                         m_arlock_o,
    output logic                         m_arvalid_o,
    input  logic                         m_arready_i,
    input  logic [CORE_DATA_WIDTH-1:0]   m_rdata_i,
    input  logic [1:0]                   m_rresp_i,
    input  logic [CORE_ID_WIDTH-1:0]     m_rid_i,
    input  logic [CORE_USER_WIDTH-1:0]   m_ruser_i,
    input  logic                         m_rlast_i,
    input  logic                         m_rvalid_i,
    output logic                         m_rready_o
);

    localparam int unsigned HOST_STRB_WIDTH = HOST_DATA_WIDTH / 8;
    localparam int unsigned CORE_STRB_WIDTH = CORE_DATA_WIDTH / 8;
    localparam int unsigned LANE_COUNT = HOST_DATA_WIDTH / CORE_DATA_WIDTH;
    localparam int unsigned LANE_INDEX_WIDTH = (LANE_COUNT > 1) ? $clog2(LANE_COUNT) : 1;
    localparam logic [1:0] RESP_OKAY   = 2'b00;
    localparam logic [1:0] RESP_SLVERR = 2'b10;

    logic [HOST_ADDR_WIDTH-1:0]   awaddr_q;
    logic [HOST_DATA_WIDTH-1:0]   wdata_q;
    logic [HOST_STRB_WIDTH-1:0]   wstrb_q;
    logic                         have_aw_q;
    logic                         have_w_q;
    logic                         issue_aw_q;
    logic                         issue_w_q;
    logic                         wait_b_q;

    logic [HOST_ADDR_WIDTH-1:0]   araddr_q;
    logic                         issue_ar_q;
    logic                         wait_r_q;
    logic [LANE_INDEX_WIDTH-1:0] read_lane_q;

    function automatic logic [CORE_ADDR_WIDTH-1:0] local_address(
        input logic [HOST_ADDR_WIDTH-1:0] addr
    );
        logic [CORE_ADDR_WIDTH-1:0] native_addr;
        native_addr = '0;
        native_addr = addr;
        return native_addr;
    endfunction

    function automatic int unsigned host_lane(input logic [HOST_ADDR_WIDTH-1:0] addr);
        if (LANE_COUNT == 1) return 0;
        return (addr / CORE_STRB_WIDTH) % LANE_COUNT;
    endfunction

    function automatic logic strobe_is_legal(
        input logic [HOST_ADDR_WIDTH-1:0] addr,
        input logic [HOST_STRB_WIDTH-1:0] strb
    );
        int unsigned lane;
        logic valid;
        lane = host_lane(addr);
        valid = 1'b1;
        for (int unsigned i = 0; i < HOST_STRB_WIDTH; i++) begin
            if ((i / CORE_STRB_WIDTH) != lane && strb[i]) valid = 1'b0;
        end
        return valid;
    endfunction

    function automatic logic [CORE_DATA_WIDTH-1:0] select_write_data(
        input logic [HOST_ADDR_WIDTH-1:0] addr,
        input logic [HOST_DATA_WIDTH-1:0] data
    );
        int unsigned lane;
        lane = host_lane(addr);
        return data[lane*CORE_DATA_WIDTH +: CORE_DATA_WIDTH];
    endfunction

    function automatic logic [CORE_STRB_WIDTH-1:0] select_write_strobe(
        input logic [HOST_ADDR_WIDTH-1:0] addr,
        input logic [HOST_STRB_WIDTH-1:0] strb
    );
        int unsigned lane;
        lane = host_lane(addr);
        return strb[lane*CORE_STRB_WIDTH +: CORE_STRB_WIDTH];
    endfunction

    initial begin
        if (CORE_DATA_WIDTH != 32) $fatal(1, "I3C core data width must be 32");
        if (HOST_DATA_WIDTH != 32 && HOST_DATA_WIDTH != 64)
            $fatal(1, "HOST_DATA_WIDTH must be 32 or 64");
        if (HOST_ADDR_WIDTH < CORE_ADDR_WIDTH)
            $fatal(1, "HOST_ADDR_WIDTH must cover the I3C core address width");
    end

    assign s_awready_o = !have_aw_q && !issue_aw_q && !wait_b_q && !s_bvalid_o;
    assign s_wready_o  = !have_w_q  && !issue_w_q  && !wait_b_q && !s_bvalid_o;
    assign s_arready_o = !issue_ar_q && !wait_r_q && !s_rvalid_o;

    assign m_awaddr_o  = local_address(awaddr_q);
    assign m_awburst_o = 2'b01;
    assign m_awsize_o  = 3'd2;
    assign m_awlen_o   = 8'd0;
    assign m_awuser_o  = '0;
    assign m_awid_o    = '0;
    assign m_awlock_o  = 1'b0;
    assign m_awvalid_o = issue_aw_q;

    assign m_wdata_o   = select_write_data(awaddr_q, wdata_q);
    assign m_wstrb_o   = select_write_strobe(awaddr_q, wstrb_q);
    assign m_wuser_o   = '0;
    assign m_wlast_o   = 1'b1;
    assign m_wvalid_o  = issue_w_q;
    assign m_bready_o  = wait_b_q && !s_bvalid_o;

    assign m_araddr_o  = local_address(araddr_q);
    assign m_arburst_o = 2'b01;
    assign m_arsize_o  = 3'd2;
    assign m_arlen_o   = 8'd0;
    assign m_aruser_o  = '0;
    assign m_arid_o    = '0;
    assign m_arlock_o  = 1'b0;
    assign m_arvalid_o = issue_ar_q;
    assign m_rready_o  = wait_r_q && !s_rvalid_o;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        logic aw_done;
        logic w_done;
        int unsigned lane;

        if (!rst_ni) begin
            awaddr_q   <= '0;
            wdata_q    <= '0;
            wstrb_q    <= '0;
            have_aw_q  <= 1'b0;
            have_w_q   <= 1'b0;
            issue_aw_q <= 1'b0;
            issue_w_q  <= 1'b0;
            wait_b_q   <= 1'b0;
            s_bresp_o  <= RESP_OKAY;
            s_bvalid_o <= 1'b0;
            araddr_q   <= '0;
            issue_ar_q <= 1'b0;
            wait_r_q   <= 1'b0;
            read_lane_q <= '0;
            s_rdata_o  <= '0;
            s_rresp_o  <= RESP_OKAY;
            s_rvalid_o <= 1'b0;
        end else begin
            if (s_bvalid_o && s_bready_i) s_bvalid_o <= 1'b0;
            if (s_rvalid_o && s_rready_i) s_rvalid_o <= 1'b0;

            if (s_awvalid_i && s_awready_o) begin
                awaddr_q  <= s_awaddr_i;
                have_aw_q <= 1'b1;
            end
            if (s_wvalid_i && s_wready_o) begin
                wdata_q   <= s_wdata_i;
                wstrb_q   <= s_wstrb_i;
                have_w_q  <= 1'b1;
            end

            if (have_aw_q && have_w_q && !issue_aw_q && !issue_w_q && !wait_b_q && !s_bvalid_o) begin
                have_aw_q <= 1'b0;
                have_w_q  <= 1'b0;
                if (!strobe_is_legal(awaddr_q, wstrb_q)) begin
                    s_bresp_o  <= RESP_SLVERR;
                    s_bvalid_o <= 1'b1;
                end else begin
                    issue_aw_q <= 1'b1;
                    issue_w_q  <= 1'b1;
                end
            end

            aw_done = !issue_aw_q || m_awready_i;
            w_done  = !issue_w_q  || m_wready_i;
            if (issue_aw_q && m_awready_i) issue_aw_q <= 1'b0;
            if (issue_w_q  && m_wready_i)  issue_w_q  <= 1'b0;
            if ((issue_aw_q || issue_w_q) && aw_done && w_done) wait_b_q <= 1'b1;

            if (m_bvalid_i && m_bready_o) begin
                wait_b_q   <= 1'b0;
                s_bresp_o  <= m_bresp_i;
                s_bvalid_o <= 1'b1;
            end

            if (s_arvalid_i && s_arready_o) begin
                araddr_q <= s_araddr_i;
                lane = host_lane(s_araddr_i);
                read_lane_q <= lane[LANE_INDEX_WIDTH-1:0];
                issue_ar_q <= 1'b1;
            end
            if (issue_ar_q && m_arready_i) begin
                issue_ar_q <= 1'b0;
                wait_r_q   <= 1'b1;
            end
            if (m_rvalid_i && m_rready_o) begin
                wait_r_q   <= 1'b0;
                s_rdata_o  <= '0;
                s_rdata_o[read_lane_q*CORE_DATA_WIDTH +: CORE_DATA_WIDTH] <= m_rdata_i;
                s_rresp_o  <= m_rlast_i ? m_rresp_i : RESP_SLVERR;
                s_rvalid_o <= 1'b1;
            end
        end
    end

    logic unused_response_metadata;
    assign unused_response_metadata = ^{m_bid_i, m_buser_i, m_rid_i, m_ruser_i};

endmodule : i3c_dv_axi_adapter
