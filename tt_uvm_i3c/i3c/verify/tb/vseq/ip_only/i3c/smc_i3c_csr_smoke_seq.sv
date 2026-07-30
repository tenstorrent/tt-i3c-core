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
// File        : smc_i3c_csr_smoke_seq.sv
// Description : UVM sequence for I3C CSR smoke.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-14
//
// *****************************************************************************

class smc_i3c_csr_smoke_seq #(int ADDR_WIDTH = 32, int DATA_WIDTH = 32)
  extends axi4lite_base_seq #(ADDR_WIDTH, DATA_WIDTH);

    `uvm_object_param_utils(smc_i3c_csr_smoke_seq #(ADDR_WIDTH, DATA_WIDTH))

    localparam bit [ADDR_WIDTH-1:0] I3C_BASE_ADDR = 'h0040_0000;
    localparam bit [31:0] HCI_VERSION_RESET = 32'h0000_0120;
    localparam bit [31:0] INTR_ENABLE_MASK = 32'h0000_7c00;

    function new(string name = "smc_i3c_csr_smoke_seq");
        super.new(name);
    endfunction

    virtual task body();
        bit [1:0] resp;
        bit [DATA_WIDTH-1:0] rd;
        bit [DATA_WIDTH-1:0] wr;

        read(I3C_BASE_ADDR + 'h000, rd, resp);
        if (resp != 2'b00 || rd[31:0] !== HCI_VERSION_RESET)
            `uvm_error("SMC_I3C_CSR", $sformatf(
                "HCI_VERSION mismatch: resp=%0b data=0x%08h", resp, rd[31:0]))

        wr = '0;
        wr[31:0] = INTR_ENABLE_MASK;
        write(I3C_BASE_ADDR + 'h024, wr, 'hf, resp);
        if (resp != 2'b00)
            `uvm_error("SMC_I3C_CSR", $sformatf("INTR_STATUS_ENABLE write resp=%0b", resp))

        read(I3C_BASE_ADDR + 'h024, rd, resp);
        if (resp != 2'b00 || (rd[31:0] & INTR_ENABLE_MASK) !== INTR_ENABLE_MASK)
            `uvm_error("SMC_I3C_CSR", $sformatf(
                "INTR_STATUS_ENABLE mismatch: resp=%0b data=0x%08h", resp, rd[31:0]))

        write(I3C_BASE_ADDR + 'h024, '0, 'hf, resp);
    endtask
endclass : smc_i3c_csr_smoke_seq
