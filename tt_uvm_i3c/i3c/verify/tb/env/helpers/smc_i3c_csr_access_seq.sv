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
// File        : smc_i3c_csr_access_seq.sv
// Description : UVM sequence for I3C CSR access.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-16
//
// *****************************************************************************

class smc_i3c_csr_access_seq #(int ADDR_WIDTH = TB_ADDR_WIDTH,
                               int DATA_WIDTH = TB_DATA_WIDTH)
  extends axi4lite_base_seq #(ADDR_WIDTH, DATA_WIDTH);

    `uvm_object_param_utils(smc_i3c_csr_access_seq #(ADDR_WIDTH, DATA_WIDTH))

    bit                         write_access;
    bit [ADDR_WIDTH-1:0]        address;
    bit [DATA_WIDTH-1:0]        write_data;
    bit [(DATA_WIDTH/8)-1:0]    write_strobe;
    bit [DATA_WIDTH-1:0]        read_data;
    bit [1:0]                   response;

    function new(string name = "smc_i3c_csr_access_seq");
        super.new(name);
        write_strobe = {(DATA_WIDTH/8){1'b1}};
    endfunction

    virtual task body();
        if (write_access)
            write(address, write_data, write_strobe, response);
        else
            read(address, read_data, response);
    endtask
endclass : smc_i3c_csr_access_seq
