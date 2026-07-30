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
// File        : smc_i3c_csr_helper.sv
// Description : Helper API for I3C CSR.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-18
//
// *****************************************************************************

class smc_i3c_csr_helper #(int ADDR_WIDTH = TB_ADDR_WIDTH,
                           int DATA_WIDTH = TB_DATA_WIDTH) extends uvm_object;

    `uvm_object_param_utils(smc_i3c_csr_helper #(ADDR_WIDTH, DATA_WIDTH))

    localparam longint unsigned DEFAULT_BASE_ADDRESS = 'h0040_0000;
    localparam longint unsigned DEFAULT_WINDOW_BYTES = 'h1000;
    localparam longint unsigned HC_CONTROL_OFFSET = 'h004;
    localparam longint unsigned COMMAND_PORT_OFFSET = 'h080;
    localparam longint unsigned RESPONSE_PORT_OFFSET = 'h084;
    localparam longint unsigned PIO_CONTROL_OFFSET = 'h0b0;
    localparam longint unsigned STBY_CR_CONTROL_OFFSET = 'h184;
    localparam int unsigned HC_BUS_ENABLE_BIT = 31;
    localparam int unsigned PIO_RUN_BIT = 1;

    axi4lite_sequencer #(ADDR_WIDTH, DATA_WIDTH) bus_sqr;
    longint unsigned base_address;
    longint unsigned window_bytes;

    function new(string name = "smc_i3c_csr_helper");
        super.new(name);
        base_address = DEFAULT_BASE_ADDRESS;
        window_bytes = DEFAULT_WINDOW_BYTES;
    endfunction

    function automatic bit [63:0] build_immediate_private_write_descriptor(
        input bit [6:0] target_address,
        input bit [7:0] payload,
        input bit [2:0] transaction_id
    );
        bit [63:0] descriptor;

        descriptor = '0;
        descriptor[63:32] = {{24{1'b0}}, payload};
        descriptor[31] = 1'b1;             // TOC: terminate on completion
        descriptor[30] = 1'b1;             // WROC: generate response on completion
        descriptor[29] = 1'b0;             // RNW: private write
        descriptor[28:26] = 3'b000;         // SDR mode
        descriptor[25:23] = 3'd1;           // DTT: one immediate data byte
        descriptor[22:16] = target_address;
        descriptor[15] = 1'b0;              // CP: private transfer, not CCC
        descriptor[14:7] = 8'h00;
        descriptor[6] = 1'b0;               // I3C, not legacy I2C
        descriptor[5:3] = transaction_id;
        descriptor[2:0] = 3'b101;           // Immediate transfer, direct address
        return descriptor;
    endfunction

    protected function void validate_access(longint unsigned offset);
        if (bus_sqr == null)
            `uvm_fatal(get_type_name(), "AXI4-Lite sequencer is not configured")
        if (offset >= window_bytes)
            `uvm_fatal(get_type_name(), $sformatf(
                "CSR offset 0x%0h is outside the 0x%0h-byte I3C window",
                offset, window_bytes))
        if ((offset % (DATA_WIDTH / 8)) != 0)
            `uvm_fatal(get_type_name(), $sformatf(
                "CSR offset 0x%0h is not aligned to %0d bytes",
                offset, DATA_WIDTH / 8))
    endfunction

    virtual task read_csr(
        input  longint unsigned offset,
        output bit [DATA_WIDTH-1:0] data,
        output bit [1:0] response,
        input  uvm_sequence_base parent_seq = null
    );
        smc_i3c_csr_access_seq #(ADDR_WIDTH, DATA_WIDTH) seq;

        validate_access(offset);
        seq = smc_i3c_csr_access_seq #(ADDR_WIDTH, DATA_WIDTH)::type_id::create(
            $sformatf("i3c_csr_read_%0h", offset));
        seq.write_access = 1'b0;
        seq.address = ADDR_WIDTH'(base_address + offset);
        seq.start(bus_sqr, parent_seq);
        data = seq.read_data;
        response = seq.response;
    endtask

    virtual task write_csr(
        input longint unsigned offset,
        input bit [DATA_WIDTH-1:0] data,
        input bit [(DATA_WIDTH/8)-1:0] strobe,
        output bit [1:0] response,
        input uvm_sequence_base parent_seq = null
    );
        smc_i3c_csr_access_seq #(ADDR_WIDTH, DATA_WIDTH) seq;

        validate_access(offset);
        seq = smc_i3c_csr_access_seq #(ADDR_WIDTH, DATA_WIDTH)::type_id::create(
            $sformatf("i3c_csr_write_%0h", offset));
        seq.write_access = 1'b1;
        seq.address = ADDR_WIDTH'(base_address + offset);
        seq.write_data = data;
        seq.write_strobe = strobe;
        seq.start(bus_sqr, parent_seq);
        response = seq.response;
    endtask


    virtual task set_bus_enable(
        input bit enable,
        output bit [DATA_WIDTH-1:0] saved_control,
        output bit [1:0] read_response,
        output bit [1:0] write_response,
        input uvm_sequence_base parent_seq = null
    );
        bit [DATA_WIDTH-1:0] updated_control;

        read_csr(HC_CONTROL_OFFSET, saved_control, read_response, parent_seq);
        updated_control = saved_control;
        updated_control[HC_BUS_ENABLE_BIT] = enable;
        write_csr(HC_CONTROL_OFFSET, updated_control, {(DATA_WIDTH/8){1'b1}},
                  write_response, parent_seq);
    endtask

    virtual task prepare_controller_for_private_write(
        output bit [DATA_WIDTH-1:0] saved_stby_control,
        output bit [DATA_WIDTH-1:0] saved_pio_control,
        output bit success,
        input uvm_sequence_base parent_seq = null
    );
        longint unsigned timing_offsets [17] = '{
            'h32c, 'h330, 'h334, 'h33c, 'h340,
            'h344, 'h348, 'h350, 'h354, 'h35c,
            'h364, 'h368, 'h370, 'h378, 'h37c,
            'h384, 'h388
        };
        bit [DATA_WIDTH-1:0] timing_values [17] = '{
            DATA_WIDTH'(1),  DATA_WIDTH'(1),  DATA_WIDTH'(2),
            DATA_WIDTH'(2),  DATA_WIDTH'(14), DATA_WIDTH'(20),
            DATA_WIDTH'(70), DATA_WIDTH'(14), DATA_WIDTH'(70),
            DATA_WIDTH'(13), DATA_WIDTH'(9),  DATA_WIDTH'(9),
            DATA_WIDTH'(8),  DATA_WIDTH'(24), DATA_WIDTH'(13),
            DATA_WIDTH'(333), DATA_WIDTH'(66600)
        };
        bit [DATA_WIDTH-1:0] updated_control;
        bit [1:0] response;

        success = 1'b1;
        read_csr(STBY_CR_CONTROL_OFFSET, saved_stby_control, response, parent_seq);
        success &= response == 2'b00;
        read_csr(PIO_CONTROL_OFFSET, saved_pio_control, response, parent_seq);
        success &= response == 2'b00;

        foreach (timing_offsets[i]) begin
            write_csr(timing_offsets[i], timing_values[i],
                      {(DATA_WIDTH/8){1'b1}}, response, parent_seq);
            success &= response == 2'b00;
        end

        // STBY_CR_ENABLE_INIT=2'b11 selects the active-controller path used
        // by the upstream controller tests.
        updated_control = saved_stby_control;
        updated_control[31:30] = 2'b11;
        write_csr(STBY_CR_CONTROL_OFFSET, updated_control,
                  {(DATA_WIDTH/8){1'b1}}, response, parent_seq);
        success &= response == 2'b00;

        updated_control = saved_pio_control;
        updated_control[PIO_RUN_BIT] = 1'b1;
        write_csr(PIO_CONTROL_OFFSET, updated_control,
                  {(DATA_WIDTH/8){1'b1}}, response, parent_seq);
        success &= response == 2'b00;
    endtask

    virtual task restore_controller_mode(
        input bit [DATA_WIDTH-1:0] saved_stby_control,
        input bit [DATA_WIDTH-1:0] saved_pio_control,
        output bit success,
        input uvm_sequence_base parent_seq = null
    );
        bit [1:0] response;

        success = 1'b1;
        write_csr(PIO_CONTROL_OFFSET, saved_pio_control,
                  {(DATA_WIDTH/8){1'b1}}, response, parent_seq);
        success &= response == 2'b00;
        write_csr(STBY_CR_CONTROL_OFFSET, saved_stby_control,
                  {(DATA_WIDTH/8){1'b1}}, response, parent_seq);
        success &= response == 2'b00;
    endtask

    virtual task restore_host_control(
        input bit [DATA_WIDTH-1:0] saved_control,
        output bit [1:0] response,
        input uvm_sequence_base parent_seq = null
    );
        write_csr(HC_CONTROL_OFFSET, saved_control, {(DATA_WIDTH/8){1'b1}},
                  response, parent_seq);
    endtask

    virtual task issue_immediate_private_write(
        input bit [6:0] target_address,
        input bit [7:0] payload,
        input bit [2:0] transaction_id,
        output bit [1:0] low_word_response,
        output bit [1:0] high_word_response,
        input uvm_sequence_base parent_seq = null
    );
        bit [63:0] descriptor;

        descriptor = build_immediate_private_write_descriptor(
            target_address, payload, transaction_id);
        write_csr(COMMAND_PORT_OFFSET, descriptor[31:0],
                  {(DATA_WIDTH/8){1'b1}}, low_word_response, parent_seq);
        write_csr(COMMAND_PORT_OFFSET, descriptor[63:32],
                  {(DATA_WIDTH/8){1'b1}}, high_word_response, parent_seq);
    endtask

    virtual task read_response_descriptor(
        output bit [DATA_WIDTH-1:0] descriptor,
        output bit [1:0] response,
        input uvm_sequence_base parent_seq = null
    );
        read_csr(RESPONSE_PORT_OFFSET, descriptor, response, parent_seq);
    endtask
endclass : smc_i3c_csr_helper
