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
// File        : smc_i3c_sanity_vseq.sv
// Description : Virtual sequence for I3C sanity.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-18
//
// *****************************************************************************

class smc_i3c_sanity_vseq extends smc_peripherals_base_vseq;
    `uvm_object_utils(smc_i3c_sanity_vseq)

    localparam longint unsigned HCI_VERSION_OFFSET = 'h000;
    localparam longint unsigned INTR_ENABLE_OFFSET = 'h024;
    localparam bit [31:0] HCI_VERSION_RESET = 32'h0000_0120;
    localparam bit [31:0] INTR_ENABLE_MASK = 32'h0000_7c00;
    localparam bit [6:0] SANITY_TARGET_ADDRESS = 7'h50;
    localparam bit [7:0] SANITY_WRITE_DATA = 8'ha5;
    localparam bit [2:0] SANITY_TRANSACTION_ID = 3'h1;

    function new(string name = "smc_i3c_sanity_vseq");
        super.new(name);
    endfunction

    protected task expect_read(
        input string case_id,
        input longint unsigned offset,
        output bit [31:0] data
    );
        bit [1:0] response;

        get_i3c_csr_helper().read_csr(offset, data, response, this);
        if (response != 2'b00)
            `uvm_error(case_id, $sformatf(
                "Read offset=0x%0h returned response=%0b data=0x%08h",
                offset, response, data))
    endtask

    protected task expect_write(
        input string case_id,
        input longint unsigned offset,
        input bit [31:0] data
    );
        bit [1:0] response;

        get_i3c_csr_helper().write_csr(offset, data, 4'hf, response, this);
        if (response != 2'b00)
            `uvm_error(case_id, $sformatf(
                "Write offset=0x%0h data=0x%08h returned response=%0b",
                offset, data, response))
    endtask

    protected task run_one_byte_private_write();
        smc_i3c_csr_helper #(TB_ADDR_WIDTH, TB_DATA_WIDTH) helper;
        bit completed;
        bit [7:0] observed_address_byte;
        bit [7:0] observed_data_byte;
        bit observed_t_bit;
        bit [TB_DATA_WIDTH-1:0] saved_host_control;
        bit [TB_DATA_WIDTH-1:0] saved_stby_control;
        bit [TB_DATA_WIDTH-1:0] saved_pio_control;
        bit [TB_DATA_WIDTH-1:0] response_descriptor;
        bit controller_ready;
        bit controller_restored;
        bit [1:0] read_response;
        bit [1:0] write_response;
        bit [1:0] command_low_response;
        bit [1:0] command_high_response;
        bit [1:0] response_port_response;
        bit [1:0] restore_response;

        helper = get_i3c_csr_helper();
        if (vseq_ctx.cfg.vif == null)
            `uvm_fatal("SMC_I3C_SANITY_BUS", "Missing I3C sanity target BFM interface")

        helper.prepare_controller_for_private_write(
            saved_stby_control, saved_pio_control, controller_ready, this);
        if (!controller_ready) begin
            `uvm_error("SMC_I3C_SANITY_PREPARE",
                       "Failed to configure I3C timing, controller mode, or PIO run")
            return;
        end

        helper.set_bus_enable(1'b1, saved_host_control, read_response,
                              write_response, this);
        if (read_response != 2'b00 || write_response != 2'b00) begin
            `uvm_error("SMC_I3C_SANITY_ENABLE", $sformatf(
                "Failed to enable I3C bus: read_resp=%0b write_resp=%0b",
                read_response, write_response))
            return;
        end

        repeat (10)
            @(posedge vseq_ctx.cfg.vif.clk);

        fork
            vseq_ctx.cfg.vif.respond_one_byte_private_write(
                completed, observed_address_byte, observed_data_byte,
                observed_t_bit);
            helper.issue_immediate_private_write(
                SANITY_TARGET_ADDRESS, SANITY_WRITE_DATA,
                SANITY_TRANSACTION_ID, command_low_response,
                command_high_response, this);
        join

        if (command_low_response != 2'b00 || command_high_response != 2'b00)
            `uvm_error("SMC_I3C_SANITY_COMMAND", $sformatf(
                "Command descriptor write failed: low_resp=%0b high_resp=%0b",
                command_low_response, command_high_response))

        if (!completed) begin
            `uvm_error("SMC_I3C_SANITY_TIMEOUT",
                       "Timed out waiting for complete START/address/data/T-bit/STOP transaction")
        end else begin
            if (observed_address_byte !== {SANITY_TARGET_ADDRESS, 1'b0})
                `uvm_error("SMC_I3C_SANITY_ADDRESS", $sformatf(
                    "Address mismatch: expected=0x%02h actual=0x%02h",
                    {SANITY_TARGET_ADDRESS, 1'b0}, observed_address_byte))
            if (observed_data_byte !== SANITY_WRITE_DATA)
                `uvm_error("SMC_I3C_SANITY_DATA", $sformatf(
                    "Data mismatch: expected=0x%02h actual=0x%02h",
                    SANITY_WRITE_DATA, observed_data_byte))
            if (((^observed_data_byte) ^ observed_t_bit) !== 1'b1)
                `uvm_error("SMC_I3C_SANITY_TBIT", $sformatf(
                    "Invalid odd parity/T-bit: data=0x%02h t_bit=%0b",
                    observed_data_byte, observed_t_bit))
            if (vseq_ctx.cfg.vif.sanity_scl_rise_count != 18)
                `uvm_error("SMC_I3C_SANITY_SCL_COUNT", $sformatf(
                    "Incomplete bus frame: expected 18 sampled SCL rising edges, got %0d",
                    vseq_ctx.cfg.vif.sanity_scl_rise_count))

            repeat (10)
                @(posedge vseq_ctx.cfg.vif.clk);
            helper.read_response_descriptor(response_descriptor,
                                            response_port_response, this);
            if (response_port_response != 2'b00)
                `uvm_error("SMC_I3C_SANITY_RESPONSE", $sformatf(
                    "Response descriptor read failed: response=%0b",
                    response_port_response))
            else begin
                if (response_descriptor[31:28] !== 4'h0)
                    `uvm_error("SMC_I3C_SANITY_RESPONSE_ERROR", $sformatf(
                        "Transaction completed with error status=0x%0h descriptor=0x%08h",
                        response_descriptor[31:28], response_descriptor))
                if (response_descriptor[27:24] !== {1'b0, SANITY_TRANSACTION_ID})
                    `uvm_error("SMC_I3C_SANITY_RESPONSE_TID", $sformatf(
                        "Response TID mismatch: expected=%0d actual=%0d",
                        SANITY_TRANSACTION_ID, response_descriptor[27:24]))
                // HCI write responses report the number of bytes left
                // untransferred, so a successful write returns zero.
                if (response_descriptor[15:0] !== 16'd0)
                    `uvm_error("SMC_I3C_SANITY_RESPONSE_LENGTH", $sformatf(
                        "Response remaining length mismatch: expected=0 actual=%0d",
                        response_descriptor[15:0]))
            end
        end

        helper.restore_host_control(saved_host_control, restore_response, this);
        if (restore_response != 2'b00)
            `uvm_error("SMC_I3C_SANITY_RESTORE_CONTROL", $sformatf(
                "Failed to restore HC_CONTROL: response=%0b", restore_response))

        helper.restore_controller_mode(saved_stby_control, saved_pio_control,
                                       controller_restored, this);
        if (!controller_restored)
            `uvm_error("SMC_I3C_SANITY_RESTORE_MODE",
                       "Failed to restore PIO_CONTROL or STBY_CR_CONTROL")

        `uvm_info("SMC_I3C_SANITY_BUS", $sformatf(
            "Private write observed: address=0x%02h data=0x%02h t_bit=%0b scl_edges=%0d stop=%0b response=0x%08h",
            observed_address_byte, observed_data_byte, observed_t_bit,
            vseq_ctx.cfg.vif.sanity_scl_rise_count,
            vseq_ctx.cfg.vif.sanity_stop_seen, response_descriptor), UVM_LOW)
    endtask

    virtual task body();
        bit [31:0] data;
        bit [31:0] saved_intr_enable;
        bit [31:0] patterns [4];

        super.body();
        if (!vseq_ctx.cfg.has_rtl)
            `uvm_fatal("SMC_I3C_MODE", "smc_i3c_sanity_test requires DUT_MODE=rtl")

        patterns[0] = 32'h0000_0400;
        patterns[1] = 32'h0000_1800;
        patterns[2] = 32'h0000_6000;
        patterns[3] = INTR_ENABLE_MASK;

        expect_read("SMC_I3C_SANITY_VERSION", HCI_VERSION_OFFSET, data);
        if (data !== HCI_VERSION_RESET)
            `uvm_error("SMC_I3C_SANITY_VERSION", $sformatf(
                "HCI_VERSION mismatch: expected=0x%08h actual=0x%08h",
                HCI_VERSION_RESET, data))

        expect_read("SMC_I3C_SANITY_SAVE", INTR_ENABLE_OFFSET, saved_intr_enable);
        foreach (patterns[i]) begin
            expect_write($sformatf("SMC_I3C_SANITY_WRITE_%0d", i),
                         INTR_ENABLE_OFFSET, patterns[i]);
            expect_read($sformatf("SMC_I3C_SANITY_READ_%0d", i),
                        INTR_ENABLE_OFFSET, data);
            if ((data & INTR_ENABLE_MASK) !== patterns[i])
                `uvm_error("SMC_I3C_SANITY_READBACK", $sformatf(
                    "Pattern[%0d] mismatch: expected=0x%08h actual=0x%08h mask=0x%08h",
                    i, patterns[i], data, INTR_ENABLE_MASK))
        end

        expect_write("SMC_I3C_SANITY_RESTORE", INTR_ENABLE_OFFSET,
                     saved_intr_enable & INTR_ENABLE_MASK);
        expect_read("SMC_I3C_SANITY_RESTORE_CHECK", INTR_ENABLE_OFFSET, data);
        if ((data & INTR_ENABLE_MASK) !== (saved_intr_enable & INTR_ENABLE_MASK))
            `uvm_error("SMC_I3C_SANITY_RESTORE_CHECK", $sformatf(
                "Restore mismatch: expected=0x%08h actual=0x%08h",
                    saved_intr_enable & INTR_ENABLE_MASK, data & INTR_ENABLE_MASK))

        run_one_byte_private_write();

        `uvm_info("SMC_I3C_SANITY",
                  "I3C CSR and one-byte private-write sanity completed", UVM_LOW)
    endtask
endclass : smc_i3c_sanity_vseq
