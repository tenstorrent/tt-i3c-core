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
// File        : i3c_vseq_context.sv
// Description : Runtime context shared by I3C virtual sequences.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-06
//
// *****************************************************************************

class i3c_vseq_context extends uvm_object;
    `uvm_object_utils(i3c_vseq_context)

    i3c_env_cfg       cfg;
    i3c_vseq_services services;
    axi4lite_sequencer #(TB_ADDR_WIDTH, TB_DATA_WIDTH) bus_sqr;  // P6: shared VIP sqr
    i3c_csr_helper #(TB_ADDR_WIDTH, TB_DATA_WIDTH) i3c_csr_helper;
    i3c_ibi_blocked_coverage i3c_ibi_blocked_cov;
`ifdef I3C_DV_NATIVE_RTL
`ifdef I3C_DV_NATIVE_RAL
    i3c_ibi_recovery_checker i3c_ibi_recovery_checker;
`endif
`endif
`ifdef I3C_DV_NATIVE_RTL
    i3c_sequencer i3c_sqr;
    i3c_sequencer i3c_target_sqr[TB_MAX_IBI_REQUESTERS];
    i3c_sequencer i3c_secondary_sqr;
`endif
`ifdef I3C_DV_NATIVE_RAL
    i3c_ral_model i3c_ral_model;
    i3c_controller_hci_helper #(TB_ADDR_WIDTH, TB_DATA_WIDTH)
      i3c_controller_hci_helper;
`endif

    function new(string name = "i3c_vseq_context");
        super.new(name);
    endfunction
endclass : i3c_vseq_context
