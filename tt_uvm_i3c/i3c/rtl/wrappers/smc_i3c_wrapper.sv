// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 VNCHIP LABS
// Authors: Huynh Pham Anh Duy, Thai Hai Dang
//
// OCAH SMC integration wrapper around the external TT I3C core.

`timescale 1ns/1ps

module smc_i3c_wrapper #(
    parameter int unsigned HOST_ADDR_WIDTH = 32,
    parameter int unsigned HOST_DATA_WIDTH = 32,
    parameter logic [HOST_ADDR_WIDTH-1:0] BASE_ADDR = 'h0040_0000,
    parameter int unsigned WINDOW_BYTES = 4096
) (
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic                         enable_i,
    input  logic                         access_allow_i,
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

    localparam int unsigned CORE_ADDR_WIDTH = 12;
    localparam int unsigned CORE_DATA_WIDTH = 32;
    localparam int unsigned CORE_USER_WIDTH = 32;
    localparam int unsigned CORE_ID_WIDTH   = 1;

    logic core_rst_n;
    logic adapter_access_allow;
    logic [CORE_ADDR_WIDTH-1:0] axi_awaddr;
    logic [1:0] axi_awburst;
    logic [2:0] axi_awsize;
    logic [7:0] axi_awlen;
    logic [CORE_USER_WIDTH-1:0] axi_awuser;
    logic [CORE_ID_WIDTH-1:0] axi_awid;
    logic axi_awlock, axi_awvalid, axi_awready;
    logic [CORE_DATA_WIDTH-1:0] axi_wdata;
    logic [CORE_DATA_WIDTH/8-1:0] axi_wstrb;
    logic [CORE_USER_WIDTH-1:0] axi_wuser;
    logic axi_wlast, axi_wvalid, axi_wready;
    logic [1:0] axi_bresp;
    logic [CORE_ID_WIDTH-1:0] axi_bid;
    logic [CORE_USER_WIDTH-1:0] axi_buser;
    logic axi_bvalid, axi_bready;
    logic [CORE_ADDR_WIDTH-1:0] axi_araddr;
    logic [1:0] axi_arburst;
    logic [2:0] axi_arsize;
    logic [7:0] axi_arlen;
    logic [CORE_USER_WIDTH-1:0] axi_aruser;
    logic [CORE_ID_WIDTH-1:0] axi_arid;
    logic axi_arlock, axi_arvalid, axi_arready;
    logic [CORE_DATA_WIDTH-1:0] axi_rdata;
    logic [1:0] axi_rresp;
    logic [CORE_ID_WIDTH-1:0] axi_rid;
    logic [CORE_USER_WIDTH-1:0] axi_ruser;
    logic axi_rlast, axi_rvalid, axi_rready;

    assign core_rst_n = rst_ni && enable_i;
    assign adapter_access_allow = access_allow_i && enable_i;

    smc_i3c_axi_adapter #(
        .HOST_ADDR_WIDTH (HOST_ADDR_WIDTH),
        .HOST_DATA_WIDTH (HOST_DATA_WIDTH),
        .CORE_ADDR_WIDTH (CORE_ADDR_WIDTH),
        .CORE_DATA_WIDTH (CORE_DATA_WIDTH),
        .CORE_USER_WIDTH (CORE_USER_WIDTH),
        .CORE_ID_WIDTH   (CORE_ID_WIDTH),
        .BASE_ADDR       (BASE_ADDR),
        .WINDOW_BYTES    (WINDOW_BYTES)
    ) u_axi_adapter (
        .clk_i, .rst_ni, .access_allow_i(adapter_access_allow),
        .s_awaddr_i(awaddr_i), .s_awvalid_i(awvalid_i), .s_awready_o(awready_o),
        .s_wdata_i(wdata_i), .s_wstrb_i(wstrb_i), .s_wvalid_i(wvalid_i), .s_wready_o(wready_o),
        .s_bresp_o(bresp_o), .s_bvalid_o(bvalid_o), .s_bready_i(bready_i),
        .s_araddr_i(araddr_i), .s_arvalid_i(arvalid_i), .s_arready_o(arready_o),
        .s_rdata_o(rdata_o), .s_rresp_o(rresp_o), .s_rvalid_o(rvalid_o), .s_rready_i(rready_i),
        .m_awaddr_o(axi_awaddr), .m_awburst_o(axi_awburst), .m_awsize_o(axi_awsize),
        .m_awlen_o(axi_awlen), .m_awuser_o(axi_awuser), .m_awid_o(axi_awid),
        .m_awlock_o(axi_awlock), .m_awvalid_o(axi_awvalid), .m_awready_i(axi_awready),
        .m_wdata_o(axi_wdata), .m_wstrb_o(axi_wstrb), .m_wuser_o(axi_wuser),
        .m_wlast_o(axi_wlast), .m_wvalid_o(axi_wvalid), .m_wready_i(axi_wready),
        .m_bresp_i(axi_bresp), .m_bid_i(axi_bid), .m_buser_i(axi_buser),
        .m_bvalid_i(axi_bvalid), .m_bready_o(axi_bready),
        .m_araddr_o(axi_araddr), .m_arburst_o(axi_arburst), .m_arsize_o(axi_arsize),
        .m_arlen_o(axi_arlen), .m_aruser_o(axi_aruser), .m_arid_o(axi_arid),
        .m_arlock_o(axi_arlock), .m_arvalid_o(axi_arvalid), .m_arready_i(axi_arready),
        .m_rdata_i(axi_rdata), .m_rresp_i(axi_rresp), .m_rid_i(axi_rid),
        .m_ruser_i(axi_ruser), .m_rlast_i(axi_rlast), .m_rvalid_i(axi_rvalid),
        .m_rready_o(axi_rready)
    );

    i3c_wrapper #(
        .AxiDataWidth (CORE_DATA_WIDTH),
        .AxiAddrWidth (CORE_ADDR_WIDTH),
        .AxiUserWidth (CORE_USER_WIDTH),
        .AxiIdWidth   (CORE_ID_WIDTH)
    ) u_i3c_core (
        .clk_i,
        .rst_ni(core_rst_n),
        .araddr_i(axi_araddr), .arburst_i(axi_arburst), .arsize_i(axi_arsize),
        .arlen_i(axi_arlen), .aruser_i(axi_aruser), .arid_i(axi_arid),
        .arlock_i(axi_arlock), .arvalid_i(axi_arvalid), .arready_o(axi_arready),
        .rdata_o(axi_rdata), .rresp_o(axi_rresp), .rid_o(axi_rid), .ruser_o(axi_ruser),
        .rlast_o(axi_rlast), .rvalid_o(axi_rvalid), .rready_i(axi_rready),
        .awaddr_i(axi_awaddr), .awburst_i(axi_awburst), .awsize_i(axi_awsize),
        .awlen_i(axi_awlen), .awuser_i(axi_awuser), .awid_i(axi_awid),
        .awlock_i(axi_awlock), .awvalid_i(axi_awvalid), .awready_o(axi_awready),
        .wdata_i(axi_wdata), .wstrb_i(axi_wstrb), .wuser_i(axi_wuser),
        .wlast_i(axi_wlast), .wvalid_i(axi_wvalid), .wready_o(axi_wready),
        .bresp_o(axi_bresp), .bid_o(axi_bid), .buser_o(axi_buser),
        .bvalid_o(axi_bvalid), .bready_i(axi_bready),
`ifdef AXI_ID_FILTERING
        .disable_id_filtering_i(1'b1),
        .priv_ids_i('{default:'0}),
`endif
        .scl_i, .sda_i, .scl_o, .sda_o, .scl_oe(scl_oe_o), .sda_oe(sda_oe_o),
        .sel_od_pp_o, .recovery_payload_available_o, .recovery_image_activated_o,
        .peripheral_reset_o, .peripheral_reset_done_i, .escalated_reset_o, .irq_o
    );

endmodule : smc_i3c_wrapper
