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
// File        : i3c_dv_wrapper.sv
// Description : Thin generic DV boundary around the native I3C wrapper.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-09-08
//
// *****************************************************************************

`timescale 1ns/1ps

module i3c_dv_wrapper #(
    parameter int unsigned HOST_ADDR_WIDTH = 32,
    parameter int unsigned HOST_DATA_WIDTH = 32,
    parameter int unsigned CORE_ADDR_WIDTH = 12,
    parameter int unsigned CORE_DATA_WIDTH = 32,
    parameter int unsigned CORE_USER_WIDTH = 32,
    parameter int unsigned CORE_ID_WIDTH   = 1
) (
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic [HOST_ADDR_WIDTH-1:0]   awaddr_i,
    input  logic                         awvalid_i,
    output logic                         awready_o,
    input  logic [HOST_DATA_WIDTH-1:0]   wdata_i,
    input  logic [HOST_DATA_WIDTH/8-1:0] wstrb_i,
    input  logic                         wvalid_i,
    output logic                         wready_o,
    output logic [1:0]                   bresp_o,
    output logic                         bvalid_o,
    input  logic                         bready_i,
    input  logic [HOST_ADDR_WIDTH-1:0]   araddr_i,
    input  logic                         arvalid_i,
    output logic                         arready_o,
    output logic [HOST_DATA_WIDTH-1:0]   rdata_o,
    output logic [1:0]                   rresp_o,
    output logic                         rvalid_o,
    input  logic                         rready_i,
    input  logic                         scl_i,
    input  logic                         sda_i,
    output logic                         scl_o,
    output logic                         sda_o,
    output logic                         scl_oe_o,
    output logic                         sda_oe_o,
    output logic                         sel_od_pp_o,
    output logic                         recovery_payload_available_o,
    output logic                         recovery_image_activated_o,
    output logic                         peripheral_reset_o,
    input  logic                         peripheral_reset_done_i,
    output logic                         escalated_reset_o,
    output logic                         irq_o
);

    logic [CORE_ADDR_WIDTH-1:0] core_awaddr;
    logic [1:0]                 core_awburst;
    logic [2:0]                 core_awsize;
    logic [7:0]                 core_awlen;
    logic [CORE_USER_WIDTH-1:0] core_awuser;
    logic [CORE_ID_WIDTH-1:0]   core_awid;
    logic                       core_awlock, core_awvalid, core_awready;
    logic [CORE_DATA_WIDTH-1:0] core_wdata;
    logic [CORE_DATA_WIDTH/8-1:0] core_wstrb;
    logic [CORE_USER_WIDTH-1:0] core_wuser;
    logic                       core_wlast, core_wvalid, core_wready;
    logic [1:0]                 core_bresp;
    logic [CORE_ID_WIDTH-1:0]   core_bid;
    logic [CORE_USER_WIDTH-1:0] core_buser;
    logic                       core_bvalid, core_bready;
    logic [CORE_ADDR_WIDTH-1:0] core_araddr;
    logic [1:0]                 core_arburst;
    logic [2:0]                 core_arsize;
    logic [7:0]                 core_arlen;
    logic [CORE_USER_WIDTH-1:0] core_aruser;
    logic [CORE_ID_WIDTH-1:0]   core_arid;
    logic                       core_arlock, core_arvalid, core_arready;
    logic [CORE_DATA_WIDTH-1:0] core_rdata;
    logic [1:0]                 core_rresp;
    logic [CORE_ID_WIDTH-1:0]   core_rid;
    logic [CORE_USER_WIDTH-1:0] core_ruser;
    logic                       core_rlast, core_rvalid, core_rready;

    i3c_dv_axi_adapter #(
        .HOST_ADDR_WIDTH (HOST_ADDR_WIDTH),
        .HOST_DATA_WIDTH (HOST_DATA_WIDTH),
        .CORE_ADDR_WIDTH (CORE_ADDR_WIDTH),
        .CORE_DATA_WIDTH (CORE_DATA_WIDTH),
        .CORE_USER_WIDTH (CORE_USER_WIDTH),
        .CORE_ID_WIDTH   (CORE_ID_WIDTH)
    ) u_axi_adapter (
        .clk_i,
        .rst_ni,
        .s_awaddr_i (awaddr_i),
        .s_awvalid_i(awvalid_i),
        .s_awready_o(awready_o),
        .s_wdata_i  (wdata_i),
        .s_wstrb_i  (wstrb_i),
        .s_wvalid_i (wvalid_i),
        .s_wready_o (wready_o),
        .s_bresp_o  (bresp_o),
        .s_bvalid_o (bvalid_o),
        .s_bready_i (bready_i),
        .s_araddr_i (araddr_i),
        .s_arvalid_i(arvalid_i),
        .s_arready_o(arready_o),
        .s_rdata_o  (rdata_o),
        .s_rresp_o  (rresp_o),
        .s_rvalid_o (rvalid_o),
        .s_rready_i (rready_i),
        .m_awaddr_o (core_awaddr),
        .m_awburst_o(core_awburst),
        .m_awsize_o (core_awsize),
        .m_awlen_o  (core_awlen),
        .m_awuser_o (core_awuser),
        .m_awid_o   (core_awid),
        .m_awlock_o (core_awlock),
        .m_awvalid_o(core_awvalid),
        .m_awready_i(core_awready),
        .m_wdata_o  (core_wdata),
        .m_wstrb_o  (core_wstrb),
        .m_wuser_o  (core_wuser),
        .m_wlast_o  (core_wlast),
        .m_wvalid_o (core_wvalid),
        .m_wready_i (core_wready),
        .m_bresp_i  (core_bresp),
        .m_bid_i    (core_bid),
        .m_buser_i  (core_buser),
        .m_bvalid_i (core_bvalid),
        .m_bready_o (core_bready),
        .m_araddr_o (core_araddr),
        .m_arburst_o(core_arburst),
        .m_arsize_o (core_arsize),
        .m_arlen_o  (core_arlen),
        .m_aruser_o (core_aruser),
        .m_arid_o   (core_arid),
        .m_arlock_o (core_arlock),
        .m_arvalid_o(core_arvalid),
        .m_arready_i(core_arready),
        .m_rdata_i  (core_rdata),
        .m_rresp_i  (core_rresp),
        .m_rid_i    (core_rid),
        .m_ruser_i  (core_ruser),
        .m_rlast_i  (core_rlast),
        .m_rvalid_i (core_rvalid),
        .m_rready_o (core_rready)
    );

    i3c_wrapper #(
        .AxiDataWidth (CORE_DATA_WIDTH),
        .AxiAddrWidth (CORE_ADDR_WIDTH),
        .AxiUserWidth (CORE_USER_WIDTH),
        .AxiIdWidth   (CORE_ID_WIDTH)
    ) u_i3c_core (
        .clk_i,
        .rst_ni,
        .araddr_i(core_araddr), .arburst_i(core_arburst), .arsize_i(core_arsize),
        .arlen_i(core_arlen), .aruser_i(core_aruser), .arid_i(core_arid),
        .arlock_i(core_arlock), .arvalid_i(core_arvalid), .arready_o(core_arready),
        .rdata_o(core_rdata), .rresp_o(core_rresp), .rid_o(core_rid), .ruser_o(core_ruser),
        .rlast_o(core_rlast), .rvalid_o(core_rvalid), .rready_i(core_rready),
        .awaddr_i(core_awaddr), .awburst_i(core_awburst), .awsize_i(core_awsize),
        .awlen_i(core_awlen), .awuser_i(core_awuser), .awid_i(core_awid),
        .awlock_i(core_awlock), .awvalid_i(core_awvalid), .awready_o(core_awready),
        .wdata_i(core_wdata), .wstrb_i(core_wstrb), .wuser_i(core_wuser),
        .wlast_i(core_wlast), .wvalid_i(core_wvalid), .wready_o(core_wready),
        .bresp_o(core_bresp), .bid_o(core_bid), .buser_o(core_buser),
        .bvalid_o(core_bvalid), .bready_i(core_bready),
`ifdef AXI_ID_FILTERING
        .disable_id_filtering_i(1'b1),
        .priv_ids_i('{default:'0}),
`endif
        .scl_i, .sda_i, .scl_o, .sda_o, .scl_oe(scl_oe_o), .sda_oe(sda_oe_o),
        .sel_od_pp_o, .recovery_payload_available_o, .recovery_image_activated_o,
        .peripheral_reset_o, .peripheral_reset_done_i, .escalated_reset_o, .irq_o
    );

endmodule : i3c_dv_wrapper
