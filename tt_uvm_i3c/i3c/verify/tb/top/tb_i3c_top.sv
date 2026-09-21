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
// File        : tb_i3c_top.sv
// Description : Top-level UVM testbench for I3C verification environment.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-06
//
// *****************************************************************************

`timescale 1ns/1ps

`ifndef VERDI_WAVE_ONLY
`include "uvm_macros.svh"
`endif

import i3c_tb_params_pkg::*;
`ifndef VERDI_WAVE_ONLY
import i3c_test_pkg::*;
import i3c_report_pkg::*;
`endif

module tb_i3c_top;
    logic clk;
    logic rst_n;
    int   clk_half_period_ps = TB_CLK_HALF_NS * 1000;

    tri1 i3c_scl_bus;
    wand i3c_sda_bus;
    pullup (i3c_sda_bus);

    initial begin
        clk   = 1'b0;
        rst_n = 1'b0;
        #(TB_RESET_ASSERT_NS * 1ns);
        rst_n = 1'b1;
    end

    always begin
        #(clk_half_period_ps * 1ps);
        clk = ~clk;
    end

    i3c_tb_if u_i3c_tb_if (
        .clk     (clk),
        .rst_n   (rst_n),
        .i3c_scl (i3c_scl_bus),
        .i3c_sda (i3c_sda_bus)
    );

    i3c_if u_i3c_if (
        .clk_i  (clk),
        .rst_ni (rst_n),
        .scl_io (i3c_scl_bus),
        .sda_io (i3c_sda_bus)
    );
    i3c_if u_i3c_target_if_1 (
        .clk_i  (clk),
        .rst_ni (rst_n),
        .scl_io (i3c_scl_bus),
        .sda_io (i3c_sda_bus)
    );
    i3c_if u_i3c_target_if_2 (
        .clk_i  (clk),
        .rst_ni (rst_n),
        .scl_io (i3c_scl_bus),
        .sda_io (i3c_sda_bus)
    );
    i3c_if u_i3c_target_if_3 (
        .clk_i  (clk),
        .rst_ni (rst_n),
        .scl_io (i3c_scl_bus),
        .sda_io (i3c_sda_bus)
    );

    // Shared AXI4-Lite register-access bus for the native I3C wrapper.
    axi4lite_if #(TB_ADDR_WIDTH, TB_DATA_WIDTH) u_axi4lite_if (clk, rst_n);

    logic i3c_scl_o;
    logic i3c_sda_o;
    logic i3c_scl_oe;
    logic i3c_sda_oe;
    logic i3c_sel_od_pp;
    logic i3c_sda_pad_oe;
    logic i3c_recovery_payload_available;
    logic i3c_recovery_image_activated;
    logic i3c_peripheral_reset;
    logic i3c_escalated_reset;
    logic i3c_irq;
    logic ibi_sva_enable;
    logic ibi_controller_sva_enable;
    logic ibi_target_sva_enable;
    logic i3c_controller_pad_enable;

    initial begin : ibi_controller_sva_config
        string test_name;
        string ibi_test_prefix;
        string controller_test_prefix;
        string sanity_test_name;
        int role;

        ibi_test_prefix = "i3c_ibi_";
        controller_test_prefix = "i3c_ibi_controller_";
        sanity_test_name = "i3c_sanity_test";
        ibi_sva_enable = 1'b0;
        ibi_controller_sva_enable = 1'b0;
        ibi_target_sva_enable = 1'b0;
        i3c_controller_pad_enable = 1'b0;
        if ($value$plusargs("UVM_TESTNAME=%s", test_name)) begin
            if (test_name.len() >= ibi_test_prefix.len())
                ibi_sva_enable =
                    (test_name.substr(0, ibi_test_prefix.len() - 1) ==
                     ibi_test_prefix);
            if (ibi_sva_enable &&
                (test_name.len() >= controller_test_prefix.len()))
                ibi_controller_sva_enable =
                    (test_name.substr(0, controller_test_prefix.len() - 1) ==
                     controller_test_prefix);
            ibi_target_sva_enable =
                ibi_sva_enable && !ibi_controller_sva_enable;
            i3c_controller_pad_enable =
                ibi_controller_sva_enable || (test_name == sanity_test_name);
        end
        if ($value$plusargs("I3C_DUT_CONTROLLER=%0d", role))
            i3c_controller_pad_enable = role == 1;
        if ($value$plusargs("IBI_DUT_CONTROLLER=%0d", role)) begin
            ibi_sva_enable = 1'b1;
            ibi_controller_sva_enable = role == 1;
            ibi_target_sva_enable = role == 0;
            i3c_controller_pad_enable = role == 1;
        end
    end

    // Active-controller mode does not drive the core sda_oe output; that
    // signal is reserved for target mode. Match the upstream controller
    // harness by deriving the pad enable from mode and data. Keep target mode
    // on the explicit core output so its independent release control remains
    // observable.
    //
    // Model a real open-drain pad: only pull a line low when the core actively
    // drives a KNOWN 0, otherwise release to the tri1/wand pull-up. At the end
    // of a controller transfer the core deasserts its drivers and leaves the
    // data outputs (i3c_scl_o/i3c_sda_o/i3c_sel_od_pp) at x (don't-care because
    // the real pad OE is low). Keying the drive off the raw data value would
    // then push an active x onto the bus, which the pull-up cannot override, so
    // the bus latches x for the rest of the run. Using ===/known-0 guards keeps
    // an unknown core output from ever reaching the bus, so it returns to a
    // clean idle 1.
    assign i3c_sda_pad_oe = i3c_controller_pad_enable ?
                            ((i3c_sel_od_pp === 1'b1) || (i3c_sda_o === 1'b0)) :
                            i3c_sda_oe;
    assign i3c_scl_bus = (i3c_scl_o === 1'b0) ? 1'b0 : 1'bz;
    assign i3c_sda_bus = (i3c_sda_pad_oe === 1'b1) ? i3c_sda_o : 1'bz;

    i3c_dv_wrapper #(
        .HOST_ADDR_WIDTH (TB_ADDR_WIDTH),
        .HOST_DATA_WIDTH (TB_DATA_WIDTH)
    ) u_dut (
        .clk_i (clk), .rst_ni (rst_n),
        .awaddr_i (u_axi4lite_if.awaddr), .awvalid_i (u_axi4lite_if.awvalid),
        .awready_o (u_axi4lite_if.awready), .wdata_i (u_axi4lite_if.wdata),
        .wstrb_i (u_axi4lite_if.wstrb), .wvalid_i (u_axi4lite_if.wvalid),
        .wready_o (u_axi4lite_if.wready), .bresp_o (u_axi4lite_if.bresp),
        .bvalid_o (u_axi4lite_if.bvalid), .bready_i (u_axi4lite_if.bready),
        .araddr_i (u_axi4lite_if.araddr), .arvalid_i (u_axi4lite_if.arvalid),
        .arready_o (u_axi4lite_if.arready), .rdata_o (u_axi4lite_if.rdata),
        .rresp_o (u_axi4lite_if.rresp), .rvalid_o (u_axi4lite_if.rvalid),
        .rready_i (u_axi4lite_if.rready),
        .scl_i (i3c_scl_bus), .sda_i (i3c_sda_bus),
        .scl_o (i3c_scl_o), .sda_o (i3c_sda_o),
        .scl_oe_o (i3c_scl_oe), .sda_oe_o (i3c_sda_oe),
        .sel_od_pp_o (i3c_sel_od_pp),
        .recovery_payload_available_o (i3c_recovery_payload_available),
        .recovery_image_activated_o (i3c_recovery_image_activated),
        .peripheral_reset_o (i3c_peripheral_reset),
        .peripheral_reset_done_i (1'b1),
        .escalated_reset_o (i3c_escalated_reset),
        .irq_o (i3c_irq)
    );
    assign u_i3c_tb_if.dut_present = 1'b1;

    i3c_ibi_bus_sva u_i3c_ibi_bus_sva (
        .clk,
        .rst_n,
        .enable(ibi_sva_enable),
        .scl(i3c_scl_bus),
        .sda(i3c_sda_bus),
        .dut_sda_drive_enable(i3c_sda_pad_oe),
        .dut_sda_value(i3c_sda_o),
        .irq(i3c_irq)
    );
    i3c_ibi_controller_sva u_i3c_ibi_controller_sva (
        .clk,
        .rst_n,
        .enable(ibi_controller_sva_enable),
        .suppress(u_i3c_tb_if.i3c_controller_ibi_sva_suppress),
        .scl(i3c_scl_bus),
        .sda(i3c_sda_bus),
        .target_addr(u_i3c_tb_if.i3c_controller_expected_addr),
        .expected_ack(u_i3c_tb_if.i3c_controller_expected_ack)
    );
    i3c_ibi_target_sva u_i3c_ibi_target_sva (
        .clk,
        .rst_n,
        .enable(ibi_target_sva_enable),
        .scl(i3c_scl_bus),
        .sda(i3c_sda_bus),
        .dut_sda_drive_enable(i3c_sda_oe),
        .dut_sda_value(i3c_sda_o),
        .target_addr(u_i3c_tb_if.i3c_controller_expected_addr)
    );
    i3c_ibi_protocol_sva u_i3c_ibi_protocol_sva (
        .clk,
        .rst_n,
        .enable(ibi_sva_enable),
        .attempt_seq(u_i3c_tb_if.i3c_sva_attempt_seq),
        .attempt_role(u_i3c_tb_if.i3c_sva_attempt_role),
        .attempt_addr_class(
          u_i3c_tb_if.i3c_sva_attempt_addr_class),
        .attempt_bcr(u_i3c_tb_if.i3c_sva_attempt_bcr),
        .attempt_ibi_enabled(
          u_i3c_tb_if.i3c_sva_attempt_ibi_enabled),
        .attempt_requester_count(
          u_i3c_tb_if.i3c_sva_attempt_requester_count),
        .attempt_arb_outcome(
          u_i3c_tb_if.i3c_sva_attempt_arb_outcome),
        .attempt_bus_state(
          u_i3c_tb_if.i3c_sva_attempt_bus_state),
        .completion_seq(u_i3c_tb_if.i3c_sva_completion_seq),
        .completion_transaction_id(
          u_i3c_tb_if.i3c_sva_completion_transaction_id),
        .completion_role(
          u_i3c_tb_if.i3c_sva_completion_role),
        .completion_ack(u_i3c_tb_if.i3c_sva_completion_ack),
        .completion_retry_count(
          u_i3c_tb_if.i3c_sva_completion_retry_count),
        .completion_terminal_status(
          u_i3c_tb_if.i3c_sva_completion_terminal_status),
        .completion_mdb_present(
          u_i3c_tb_if.i3c_sva_completion_mdb_present),
        .completion_mdb(u_i3c_tb_if.i3c_sva_completion_mdb),
        .completion_payload_len(
          u_i3c_tb_if.i3c_sva_completion_payload_len),
        .completion_dat_match(
          u_i3c_tb_if.i3c_sva_completion_dat_match),
        .completion_payload_policy(
          u_i3c_tb_if.i3c_sva_completion_payload_policy),
        .completion_ibi_enabled(
          u_i3c_tb_if.i3c_sva_completion_ibi_enabled),
        .completion_error_kind(
          u_i3c_tb_if.i3c_sva_completion_error_kind),
        .completion_recovery_result(
          u_i3c_tb_if.i3c_sva_completion_recovery_result),
        .expected_content_valid(
          u_i3c_tb_if.i3c_sva_expected_content_valid),
        .expected_mdb_present(
          u_i3c_tb_if.i3c_sva_expected_mdb_present),
        .expected_mdb(u_i3c_tb_if.i3c_sva_expected_mdb),
        .expected_payload_len(
          u_i3c_tb_if.i3c_sva_expected_payload_len),
        .queue_seq(u_i3c_tb_if.i3c_sva_queue_seq),
        .queue_transaction_id(
          u_i3c_tb_if.i3c_sva_queue_transaction_id),
        .queue_record_write(
          u_i3c_tb_if.i3c_sva_queue_record_write),
        .queue_response_context_valid(
          u_i3c_tb_if.i3c_sva_queue_response_context_valid),
        .queue_response_ack(
          u_i3c_tb_if.i3c_sva_queue_response_ack),
        .queue_state(u_i3c_tb_if.i3c_sva_queue_state),
        .queue_status_source(
          u_i3c_tb_if.i3c_sva_queue_status_source),
        .queue_irq_state(
          u_i3c_tb_if.i3c_sva_queue_irq_state),
        .queue_role(u_i3c_tb_if.i3c_sva_queue_role),
        .queue_irq_enabled(
          u_i3c_tb_if.i3c_sva_queue_irq_enabled),
        .arbitration_seq(
          u_i3c_tb_if.i3c_sva_arbitration_seq),
        .requester_active(
          u_i3c_tb_if.i3c_sva_requester_active),
        .requester_winner(
          u_i3c_tb_if.i3c_sva_requester_winner),
        .requester_released(
          u_i3c_tb_if.i3c_sva_requester_released),
        .recovery_seq(u_i3c_tb_if.i3c_sva_recovery_seq),
        .recovery_role(u_i3c_tb_if.i3c_sva_recovery_role),
        .recovery_cause(u_i3c_tb_if.i3c_sva_recovery_cause),
        .recovery_result(u_i3c_tb_if.i3c_sva_recovery_result),
        .recovery_trigger_seen(
          u_i3c_tb_if.i3c_sva_recovery_trigger_seen),
        .recovery_queue_empty(
          u_i3c_tb_if.i3c_sva_recovery_queue_empty),
        .recovery_irq_low(
          u_i3c_tb_if.i3c_sva_recovery_irq_low),
        .recovery_bus_idle(
          u_i3c_tb_if.i3c_sva_recovery_bus_idle),
        .recovery_followup_expected(
          u_i3c_tb_if.i3c_sva_recovery_followup_expected),
        .recovery_forward_progress(
          u_i3c_tb_if.i3c_sva_recovery_forward_progress),
        .scl(i3c_scl_bus),
        .sda(i3c_sda_bus),
        .timing_check_enable(
          u_i3c_tb_if.i3c_controller_sva_check_enable),
        .timing_normal_active(
          u_i3c_tb_if.i3c_timing_normal_active),
        .timing_ibi_pending(
          u_i3c_tb_if.i3c_timing_ibi_pending),
        .timing_ibi_start_allowed(
          u_i3c_tb_if.i3c_timing_ibi_start_allowed)
    );
    assign u_i3c_tb_if.i3c_irq = i3c_irq;
    assign u_i3c_tb_if.i3c_recovery_payload_available = i3c_recovery_payload_available;
    assign u_i3c_tb_if.i3c_recovery_image_activated = i3c_recovery_image_activated;
    assign u_i3c_tb_if.i3c_peripheral_reset = i3c_peripheral_reset;
    assign u_i3c_tb_if.i3c_escalated_reset = i3c_escalated_reset;
    assign u_i3c_tb_if.i3c_scl_oe = i3c_scl_oe;
    assign u_i3c_tb_if.i3c_sda_oe = i3c_sda_oe;
    initial begin : dump_control
        string dump_format;
        string dump_file;

        dump_format = "none";
        dump_file = "";
        void'($value$plusargs("DV_DUMP_FORMAT=%s", dump_format));
        void'($value$plusargs("DV_DUMP_FILE=%s", dump_file));

        case (dump_format)
            "none": begin
            end
            "vcd": begin
`ifdef I3C_VCD_ENABLE
                if (dump_file == "")
                    dump_file = "i3c.vcd";
                $display("[DUMP] VCD file: %s", dump_file);
                $dumpfile(dump_file);
                $dumpvars(0, tb_i3c_top);
`else
                $error("VCD dump requested without I3C_VCD_ENABLE");
`endif
            end
            "vpd": begin
`ifdef I3C_VPD_ENABLE
                if (dump_file == "")
                    dump_file = "i3c.vpd";
                $display("[DUMP] VPD file: %s", dump_file);
                $vcdplusfile(dump_file);
                $vcdpluson;
`else
                $error("VPD dump requested without I3C_VPD_ENABLE");
`endif
            end
            "fsdb": begin
`ifdef I3C_FSDB_ENABLE
                if (dump_file == "")
                    dump_file = "i3c.fsdb";
                $display("[DUMP] FSDB file: %s", dump_file);
                $fsdbDumpfile(dump_file);
                $fsdbDumpvars(0, tb_i3c_top);
`else
                $error("FSDB dump requested without I3C_FSDB_ENABLE");
`endif
            end
            default: begin
                $error("Unsupported DV_DUMP_FORMAT=%s", dump_format);
            end
        endcase
    end

`ifndef VERDI_WAVE_ONLY
    initial begin
        i3c_report_server report_server;

        $timeformat(-9, 0, " ns", 10);
        report_server = new();
        uvm_pkg::uvm_report_server::set_server(report_server);

        uvm_pkg::uvm_config_db#(virtual i3c_tb_if)::set(
            null, "uvm_test_top", "i3c_vif", u_i3c_tb_if);
        uvm_pkg::uvm_config_db#(virtual axi4lite_if #(TB_ADDR_WIDTH, TB_DATA_WIDTH))::set(
            null, "uvm_test_top", "i3c_bus_vif", u_axi4lite_if);
        uvm_pkg::uvm_config_db#(virtual i3c_if)::set(
            null, "uvm_test_top", "i3c_vif", u_i3c_if);
        uvm_pkg::uvm_config_db#(virtual i3c_if)::set(
            null, "uvm_test_top", "i3c_target_vif_1",
            u_i3c_target_if_1);
        uvm_pkg::uvm_config_db#(virtual i3c_if)::set(
            null, "uvm_test_top", "i3c_target_vif_2",
            u_i3c_target_if_2);
        uvm_pkg::uvm_config_db#(virtual i3c_if)::set(
            null, "uvm_test_top", "i3c_target_vif_3",
            u_i3c_target_if_3);
        // Compatibility key used by the existing two-requester tests.
        uvm_pkg::uvm_config_db#(virtual i3c_if)::set(
            null, "uvm_test_top", "i3c_secondary_vif",
            u_i3c_target_if_1);

        uvm_pkg::run_test();
    end
`endif
endmodule : tb_i3c_top
