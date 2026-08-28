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
// File        : smc_peripherals_base_vseq.sv
// Description : Base virtual sequence for SMC peripherals.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-18
//
// *****************************************************************************

class smc_peripherals_base_vseq extends uvm_sequence #(uvm_sequence_item);
    `uvm_object_utils(smc_peripherals_base_vseq)

    smc_peripherals_vseq_context vseq_ctx;  // 'context' is a SV keyword

    function new(string name = "smc_peripherals_base_vseq");
        super.new(name);
    endfunction

    virtual task pre_body();
        if (vseq_ctx == null &&
            !uvm_config_db#(smc_peripherals_vseq_context)::get(
                null, "uvm_test_top", "context", vseq_ctx)) begin
            `uvm_fatal(get_type_name(), "Missing smc_peripherals_vseq_context")
        end
    endtask

    virtual task body();
        if (vseq_ctx == null || vseq_ctx.services == null) begin
            `uvm_fatal(get_type_name(), "Invalid vseq context")
        end
        vseq_ctx.services.wait_reset_release();
    endtask

    virtual function smc_i3c_csr_helper #(TB_ADDR_WIDTH, TB_DATA_WIDTH)
        get_i3c_csr_helper();
        if (vseq_ctx == null || vseq_ctx.i3c_csr_helper == null) begin
            `uvm_fatal(get_type_name(), "I3C CSR helper is not configured in vseq context")
        end
        return vseq_ctx.i3c_csr_helper;
    endfunction

`ifdef SMC_USE_I3C_RAL
    virtual function smc_i3c_ral_model get_i3c_ral_model();
        if (vseq_ctx == null || vseq_ctx.i3c_ral_model == null)
            `uvm_fatal(get_type_name(), "I3C RAL model is not configured in vseq context")
        return vseq_ctx.i3c_ral_model;
    endfunction
`endif
endclass : smc_peripherals_base_vseq
