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
// File        : smc_i3c_host_accept_ibi_seq.sv
// Description : Controller-mode sequence for accepting target IBI requests.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-24
//
// *****************************************************************************

`ifndef SMC_I3C_HOST_ACCEPT_IBI_SEQ_SV
`define SMC_I3C_HOST_ACCEPT_IBI_SEQ_SV

class smc_i3c_host_broadcast_ccc_seq extends
    uvm_sequence #(i3c_seq_item, i3c_seq_item);
    `uvm_object_utils(smc_i3c_host_broadcast_ccc_seq)

    bit [7:0] ccc = RSTDAA;

    function new(string name = "smc_i3c_host_broadcast_ccc_seq");
        super.new(name);
    endfunction

    virtual task body();
        i3c_seq_item response;

        req = i3c_seq_item::type_id::create("req");
        start_item(req);
        req.i3c = 1'b1;
        req.addr = 7'h7e;
        req.dir = 1'b0;
        req.dev_ack = 1'b1;
        req.end_with_rstart = 1'b0;
        req.is_daa = 1'b0;
        req.data.delete();
        req.data.push_back(ccc);
        req.data_cnt = 1;
        req.T_bit.delete();
        req.T_bit.push_back(!(^ccc));
        req.IBI = 1'b0;
        req.IBI_ADDR = '0;
        req.IBI_START = 1'b0;
        req.IBI_ACK = 1'b0;
        finish_item(req);
        get_response(response);

        if (response == null)
            `uvm_fatal("IBI_CCC_NO_RESPONSE",
                       $sformatf("Host driver returned no response for broadcast CCC 0x%02h",
                                 ccc))
        else if (!response.dev_ack)
            `uvm_fatal("IBI_CCC_NACK",
                       $sformatf("Target NACKed required broadcast CCC 0x%02h",
                                 ccc))
    endtask
endclass : smc_i3c_host_broadcast_ccc_seq

// Generates a legal STOP without coupling the basic IBI test to broadcast-CCC
// data/parity behavior. The selected address must still be disabled in the DUT,
// The pinned driver returns one response after the address phase and consumes a
// second item to move from DrvSelectNext through STOP back to DrvIdle.
class smc_i3c_host_bus_idle_seq extends
    uvm_sequence #(i3c_seq_item, i3c_seq_item);
    `uvm_object_utils(smc_i3c_host_bus_idle_seq)

    bit [6:0] unassigned_addr;

    function new(string name = "smc_i3c_host_bus_idle_seq");
        super.new(name);
    endfunction

    virtual task body();
        i3c_seq_item address_response;
        i3c_seq_item stop_response;

        req = i3c_seq_item::type_id::create("req");
        start_item(req);
        req.i3c = 1'b1;
        req.addr = unassigned_addr;
        req.dir = 1'b0;
        req.dev_ack = 1'b0;
        req.end_with_rstart = 1'b0;
        req.is_daa = 1'b0;
        req.data.delete();
        req.data_cnt = 0;
        req.T_bit.delete();
        req.IBI = 1'b0;
        req.IBI_ADDR = '0;
        req.IBI_START = 1'b0;
        req.IBI_ACK = 1'b0;
        finish_item(req);
        get_response(address_response);

        if (address_response == null)
            `uvm_fatal("IBI_BUS_PRIME_NO_RESPONSE",
                       "Host driver returned no response for the bus-prime address")
        else if (address_response.dev_ack)
            `uvm_fatal("IBI_BUS_PRIME_ACK",
                       $sformatf("Disabled target unexpectedly ACKed address 0x%02h",
                                 unassigned_addr))

        req = i3c_seq_item::type_id::create("stop_req");
        start_item(req);
        req.i3c = 1'b1;
        req.addr = unassigned_addr;
        req.dir = 1'b0;
        req.dev_ack = 1'b0;
        req.end_with_rstart = 1'b0;
        req.is_daa = 1'b0;
        req.data.delete();
        req.data_cnt = 0;
        req.T_bit.delete();
        req.IBI = 1'b0;
        req.IBI_ADDR = '0;
        req.IBI_START = 1'b0;
        req.IBI_ACK = 1'b0;
        finish_item(req);
        get_response(stop_response);

        if (stop_response == null)
            `uvm_fatal("IBI_BUS_PRIME_STOP_NO_RESPONSE",
                       "Host driver returned no response while completing bus-prime STOP")
    endtask
endclass : smc_i3c_host_bus_idle_seq

class smc_i3c_host_respond_ibi_seq extends
    uvm_sequence #(i3c_seq_item, i3c_seq_item);
    `uvm_object_utils(smc_i3c_host_respond_ibi_seq)

    bit ibi_ack = 1'b1;
    bit response_valid;
    bit [6:0] response_addr;
    byte unsigned response_data[$];
    // Number of bytes the host samples from the target IBI (MDB + payload).
    // The push-pull read loop in i3c_driver reads exactly data_cnt bytes and
    // breaks on the last T-bit, so this must equal what the target transmits
    // (1 + payload_len). Default 1 keeps MDB-only sequences unchanged.
    int unsigned rx_byte_count = 1;

    function new(string name = "smc_i3c_host_respond_ibi_seq");
        super.new(name);
    endfunction

    virtual task body();
        i3c_seq_item response;

        response_valid = 1'b0;
        response_addr = '0;
        response_data.delete();
        req = i3c_seq_item::type_id::create("req");
        start_item(req);
        req.i3c = 1'b1;
        req.addr = 7'h7e;
        req.dir = 1'b0;
        req.dev_ack = 1'b0;
        req.end_with_rstart = 1'b0;
        req.is_daa = 1'b0;
        req.data.delete();
        req.data_cnt = rx_byte_count;
        req.T_bit.delete();
        req.IBI = 1'b1;
        // Host mode never drives IBI_ADDR; the target address is sampled into
        // response.IBI_ADDR. Keep this field zero to make that contract clear.
        req.IBI_ADDR = '0;
        req.IBI_START = 1'b1;
        req.IBI_ACK = ibi_ack;
        finish_item(req);
        get_response(response);

        if (response == null) begin
            `uvm_fatal("IBI_HOST_NO_RESPONSE",
                       $sformatf("Host driver returned no response for target IBI response ACK=%0b",
                                 ibi_ack))
        end else if (!response.IBI) begin
            `uvm_error("IBI_HOST_RESPONSE", "Host agent did not classify the transfer as IBI")
        end else begin
            response_valid = 1'b1;
            response_addr = response.IBI_ADDR;
            foreach (response.data[index])
                response_data.push_back(response.data[index]);
        end
    endtask
endclass : smc_i3c_host_respond_ibi_seq

// Keeps the controller VIP armed while a pre-filled target queue drains.
// Each entry describes one independently terminated IBI response.
class smc_i3c_host_respond_ibi_burst_seq extends
    uvm_sequence #(i3c_seq_item, i3c_seq_item);
    `uvm_object_utils(smc_i3c_host_respond_ibi_burst_seq)

    int unsigned rx_byte_count_q[$];
    bit ibi_ack_q[$];
    bit [6:0] response_addr_q[$];
    bit response_ibi_q[$];
    int unsigned response_count;

    function new(string name = "smc_i3c_host_respond_ibi_burst_seq");
        super.new(name);
    endfunction

    virtual task body();
        i3c_seq_item response;

        if (rx_byte_count_q.size() == 0)
            `uvm_fatal("IBI_BURST_EMPTY",
                       "IBI burst sequence requires at least one response")
        if (ibi_ack_q.size() != rx_byte_count_q.size())
            `uvm_fatal("IBI_BURST_CFG",
                       $sformatf("ACK count=%0d differs from receive-count entries=%0d",
                                 ibi_ack_q.size(), rx_byte_count_q.size()))

        response_count = 0;
        response_addr_q.delete();
        response_ibi_q.delete();
        foreach (rx_byte_count_q[index]) begin
            req = i3c_seq_item::type_id::create(
                $sformatf("req_%0d", index));
            start_item(req);
            req.i3c = 1'b1;
            req.addr = 7'h7e;
            req.dir = 1'b0;
            req.dev_ack = 1'b0;
            req.end_with_rstart = 1'b0;
            req.is_daa = 1'b0;
            req.data.delete();
            req.data_cnt = rx_byte_count_q[index];
            req.T_bit.delete();
            req.IBI = 1'b1;
            req.IBI_ADDR = '0;
            req.IBI_START = 1'b1;
            req.IBI_ACK = ibi_ack_q[index];
            finish_item(req);
            get_response(response);

            if (response == null)
                `uvm_fatal("IBI_BURST_NO_RESPONSE",
                           $sformatf("No host response for burst entry %0d",
                                     index))
            if (!response.IBI)
                `uvm_fatal("IBI_BURST_RESPONSE",
                           $sformatf("Burst entry %0d was not classified as IBI",
                                     index))
            response_addr_q.push_back(response.IBI_ADDR);
            response_ibi_q.push_back(response.IBI);
            response_count++;
        end
    endtask
endclass : smc_i3c_host_respond_ibi_burst_seq

// Backward-compatible ACK-only sequence used by the basic IBI test.
class smc_i3c_host_accept_ibi_seq extends smc_i3c_host_respond_ibi_seq;
    `uvm_object_utils(smc_i3c_host_accept_ibi_seq)

    function new(string name = "smc_i3c_host_accept_ibi_seq");
        super.new(name);
        ibi_ack = 1'b1;
    endfunction
endclass : smc_i3c_host_accept_ibi_seq

`endif // SMC_I3C_HOST_ACCEPT_IBI_SEQ_SV
