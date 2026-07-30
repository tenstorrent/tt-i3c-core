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
// File        : smc_peripherals_test_pkg.sv
// Description : UVM test package for SMC peripherals.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-25
//
// *****************************************************************************

package smc_peripherals_test_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import smc_peripherals_tb_params_pkg::*;
    import axi4lite_vip_pkg::*;
    import smc_i3c_coverage_pkg::*;
    import smc_peripherals_env_pkg::*;
    import smc_peripherals_vseq_pkg::*;

    `include "smc_peripherals_base_test.sv"
    `include "smc_i3c_csr_smoke_test.sv"
    `include "smc_i3c_sanity_test.sv"
    `include "ibi/smc_i3c_ibi_base_test.sv"
    `include "ibi/smc_i3c_ibi_basic_test.sv"
    `include "ibi/smc_i3c_ibi_ack_nack_test.sv"
    `include "ibi/smc_i3c_ibi_mdb_payload_test.sv"
    `include "ibi/smc_i3c_ibi_fifo_irq_test.sv"
    `include "ibi/smc_i3c_ibi_controller_receive_test.sv"
    `include "ibi/smc_i3c_ibi_controller_content_test.sv"
    `include "ibi/smc_i3c_ibi_controller_policy_test.sv"
    `include "ibi/smc_i3c_ibi_controller_multi_target_test.sv"
    `include "ibi/smc_i3c_ibi_controller_timing_context_test.sv"
`ifdef SMC_USE_I3C_RAL
    `include "smc_i3c_ral_all_regs_test.sv"
`endif
endpackage : smc_peripherals_test_pkg
