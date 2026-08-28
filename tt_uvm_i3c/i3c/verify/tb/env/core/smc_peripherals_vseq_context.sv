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
// File        : smc_peripherals_vseq_context.sv
// Description : Runtime context shared by SMC peripheral virtual sequences.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-06
//
// *****************************************************************************

class smc_peripherals_vseq_context extends uvm_object;
    `uvm_object_utils(smc_peripherals_vseq_context)

    smc_peripherals_env_cfg       cfg;
    smc_peripherals_vseq_services services;
    axi4lite_sequencer #(TB_ADDR_WIDTH, TB_DATA_WIDTH) bus_sqr;  // P6: shared VIP sqr
    smc_i3c_csr_helper #(TB_ADDR_WIDTH, TB_DATA_WIDTH) i3c_csr_helper;
    smc_i3c_ibi_blocked_coverage i3c_ibi_blocked_cov;
`ifdef SMC_USE_I3C_RTL
`ifdef SMC_USE_I3C_RAL
    smc_i3c_ibi_recovery_checker i3c_ibi_recovery_checker;
`endif
`endif
`ifdef SMC_USE_I3C_RTL
    i3c_sequencer i3c_sqr;
    i3c_sequencer i3c_target_sqr[TB_MAX_IBI_REQUESTERS];
    i3c_sequencer i3c_secondary_sqr;
`endif
`ifdef SMC_USE_I3C_RAL
    smc_i3c_ral_model i3c_ral_model;
    smc_i3c_controller_hci_helper #(TB_ADDR_WIDTH, TB_DATA_WIDTH)
      i3c_controller_hci_helper;
`endif

    function new(string name = "smc_peripherals_vseq_context");
        super.new(name);
    endfunction
endclass : smc_peripherals_vseq_context
