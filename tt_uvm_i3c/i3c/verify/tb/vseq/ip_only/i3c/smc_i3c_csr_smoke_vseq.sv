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
// File        : smc_i3c_csr_smoke_vseq.sv
// Description : Virtual sequence for I3C CSR smoke.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-14
//
// *****************************************************************************

class smc_i3c_csr_smoke_vseq extends smc_peripherals_base_vseq;
    `uvm_object_utils(smc_i3c_csr_smoke_vseq)

    function new(string name = "smc_i3c_csr_smoke_vseq");
        super.new(name);
    endfunction

    virtual task body();
        smc_i3c_csr_smoke_seq #(TB_ADDR_WIDTH, TB_DATA_WIDTH) seq;
        super.body();
        if (!vseq_ctx.cfg.has_rtl)
            `uvm_fatal("SMC_I3C_MODE", "smc_i3c_csr_smoke_test requires DUT_MODE=rtl")
        if (vseq_ctx.bus_sqr == null)
            `uvm_fatal("SMC_I3C_BUS", "I3C CSR smoke requires the local AXI-Lite agent")
        seq = smc_i3c_csr_smoke_seq #(TB_ADDR_WIDTH, TB_DATA_WIDTH)::type_id::create("seq");
        seq.start(vseq_ctx.bus_sqr);
    endtask
endclass : smc_i3c_csr_smoke_vseq
