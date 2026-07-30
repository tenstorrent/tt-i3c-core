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
// File        : axi4lite_reg_adapter.sv
// Description : UVM register adapter for AXI4-Lite transactions.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-16
//
// *****************************************************************************

class smc_i3c_axi4lite_reg_adapter #(
    int ADDR_WIDTH = TB_ADDR_WIDTH,
    int DATA_WIDTH = TB_DATA_WIDTH
) extends uvm_reg_adapter;

    `uvm_object_param_utils(smc_i3c_axi4lite_reg_adapter #(ADDR_WIDTH, DATA_WIDTH))

    function new(string name = "smc_i3c_axi4lite_reg_adapter");
        super.new(name);
        supports_byte_enable = 1;
        provides_responses = 0;
    endfunction

    virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
        axi4lite_item #(ADDR_WIDTH, DATA_WIDTH) item;
        bit [(DATA_WIDTH/8)-1:0] strobe;

        item = axi4lite_item #(ADDR_WIDTH, DATA_WIDTH)::type_id::create("ral_item");
        strobe = '0;
        for (int unsigned byte_index = 0; byte_index < (DATA_WIDTH/8); byte_index++)
            strobe[byte_index] = rw.byte_en[byte_index];
        if (strobe == '0)
            strobe = '1;

        item.write = (rw.kind == UVM_WRITE);
        item.addr = rw.addr[ADDR_WIDTH-1:0];
        item.data = item.write ? rw.data[DATA_WIDTH-1:0] : '0;
        item.strb = strobe;
        return item;
    endfunction

    virtual function void bus2reg(uvm_sequence_item bus_item,
                                  ref uvm_reg_bus_op rw);
        axi4lite_item #(ADDR_WIDTH, DATA_WIDTH) item;

        if (!$cast(item, bus_item)) begin
            `uvm_fatal("SMC_I3C_RAL_ADAPTER",
                       "bus2reg expected an axi4lite_item")
            return;
        end
        rw.kind = item.write ? UVM_WRITE : UVM_READ;
        rw.addr = item.addr;
        rw.data = item.write ? item.data : item.rdata;
        rw.status = (item.resp == 2'b00) ? UVM_IS_OK : UVM_NOT_OK;
    endfunction
endclass : smc_i3c_axi4lite_reg_adapter
