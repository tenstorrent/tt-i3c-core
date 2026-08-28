// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 VNCHIP LABS
// Authors: Huynh Pham Anh Duy, Thai Hai Dang
//
// Standalone OCAH SMC-to-TT-I3C integration top.

`timescale 1ns/1ps

module smc_peripherals_top #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 32,
    parameter logic [ADDR_WIDTH-1:0] I3C_BASE_ADDR = 'h0040_0000,
    parameter int unsigned I3C_WINDOW_BYTES = 4096
) (
    input  logic                      clk,
    input  logic                      rst_n,
    input  logic                      i3c_enable_i,
    input  logic                      i3c_access_allow_i,
    input  logic [ADDR_WIDTH-1:0]     awaddr,
    input  logic                      awvalid,
    output logic                      awready,
    input  logic [DATA_WIDTH-1:0]     wdata,
    input  logic [DATA_WIDTH/8-1:0]   wstrb,
    input  logic                      wvalid,
    output logic                      wready,
    output logic [1:0]                bresp,
    output logic                      bvalid,
    input  logic                      bready,
    input  logic [ADDR_WIDTH-1:0]     araddr,
    input  logic                      arvalid,
    output logic                      arready,
    output logic [DATA_WIDTH-1:0]     rdata,
    output logic [1:0]                rresp,
    output logic                      rvalid,
    input  logic                      rready,
    input  logic                      i3c_scl_i,
    input  logic                      i3c_sda_i,
    output logic                      i3c_scl_o,
    output logic                      i3c_sda_o,
    output logic                      i3c_scl_oe_o,
    output logic                      i3c_sda_oe_o,
    output logic                      i3c_sel_od_pp_o,
    output logic                      i3c_recovery_payload_available_o,
    output logic                      i3c_recovery_image_activated_o,
    output logic                      i3c_peripheral_reset_o,
    input  logic                      i3c_peripheral_reset_done_i,
    output logic                      i3c_escalated_reset_o,
    output logic                      i3c_irq_o
);

    smc_i3c_wrapper #(
        .HOST_ADDR_WIDTH (ADDR_WIDTH),
        .HOST_DATA_WIDTH (DATA_WIDTH),
        .BASE_ADDR       (I3C_BASE_ADDR),
        .WINDOW_BYTES    (I3C_WINDOW_BYTES)
    ) u_i3c0 (
        .clk_i(clk), .rst_ni(rst_n), .enable_i(i3c_enable_i),
        .access_allow_i(i3c_access_allow_i),
        .awaddr_i(awaddr), .awvalid_i(awvalid), .awready_o(awready),
        .wdata_i(wdata), .wstrb_i(wstrb), .wvalid_i(wvalid), .wready_o(wready),
        .bresp_o(bresp), .bvalid_o(bvalid), .bready_i(bready),
        .araddr_i(araddr), .arvalid_i(arvalid), .arready_o(arready),
        .rdata_o(rdata), .rresp_o(rresp), .rvalid_o(rvalid), .rready_i(rready),
        .scl_i(i3c_scl_i), .sda_i(i3c_sda_i), .scl_o(i3c_scl_o), .sda_o(i3c_sda_o),
        .scl_oe_o(i3c_scl_oe_o), .sda_oe_o(i3c_sda_oe_o), .sel_od_pp_o(i3c_sel_od_pp_o),
        .recovery_payload_available_o(i3c_recovery_payload_available_o),
        .recovery_image_activated_o(i3c_recovery_image_activated_o),
        .peripheral_reset_o(i3c_peripheral_reset_o),
        .peripheral_reset_done_i(i3c_peripheral_reset_done_i),
        .escalated_reset_o(i3c_escalated_reset_o), .irq_o(i3c_irq_o)
    );

endmodule : smc_peripherals_top
