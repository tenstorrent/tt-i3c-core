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
// File        : smc_peripherals_vseq_pkg.sv
// Description : Package for SMC peripheral virtual sequences.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-25
//
// *****************************************************************************

package smc_peripherals_vseq_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Wildcard imports are NOT transitive: env_pkg importing these does not
    // re-export them here, so the vseqs (axi4lite_base_seq, TB_*_WIDTH) need
    // their own imports.
    import smc_peripherals_tb_params_pkg::*;
    import axi4lite_vip_pkg::*;
    import smc_i3c_coverage_pkg::*;
    import smc_peripherals_env_pkg::*;
`ifdef SMC_USE_I3C_RTL
    import i3c_vip_pkg::*;
`endif
`ifdef SMC_USE_I3C_RAL
    import I3CCSR_uvm::*;
    import smc_peripherals_ral_pkg::*;
`endif

    `include "smc_peripherals_base_vseq.sv"
    `include "smc_i3c_csr_smoke_seq.sv"
    `include "smc_i3c_csr_smoke_vseq.sv"
    `include "smc_i3c_sanity_vseq.sv"
`ifdef SMC_USE_I3C_RTL
    `include "ibi/smc_i3c_host_accept_ibi_seq.sv"
    `include "ibi/smc_i3c_target_send_ibi_seq.sv"
    `include "ibi/smc_i3c_target_private_write_seq.sv"
`endif
    `include "ibi/smc_i3c_ibi_base_vseq.sv"
    `include "ibi/smc_i3c_ibi_basic_vseq.sv"
    `include "ibi/smc_i3c_ibi_ack_nack_vseq.sv"
    `include "ibi/smc_i3c_ibi_mdb_payload_vseq.sv"
    `include "ibi/smc_i3c_ibi_fifo_irq_vseq.sv"
    `include "ibi/smc_i3c_ibi_controller_receive_vseq.sv"
    `include "ibi/smc_i3c_ibi_controller_content_vseq.sv"
    `include "ibi/smc_i3c_ibi_controller_policy_vseq.sv"
    `include "ibi/smc_i3c_ibi_controller_multi_target_vseq.sv"
    `include "ibi/smc_i3c_ibi_controller_timing_context_vseq.sv"
`ifdef SMC_USE_I3C_RAL
    `include "smc_i3c_ral_all_regs_vseq.sv"
`endif
endpackage : smc_peripherals_vseq_pkg
