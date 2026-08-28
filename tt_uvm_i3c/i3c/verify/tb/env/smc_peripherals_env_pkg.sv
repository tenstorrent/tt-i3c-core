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
// File        : smc_peripherals_env_pkg.sv
// Description : UVM environment package for SMC peripherals.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-06
//
// *****************************************************************************

package smc_peripherals_env_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // BCR IBI capability bits shared by Controller reference checking and
    // IBI scenario construction.  Keep the values aligned with the existing
    // base IBI vseq contract.
    localparam int unsigned SMC_I3C_BCR_IBI_CAPABLE_BIT = 1;
    localparam int unsigned SMC_I3C_BCR_MDB_CAPABLE_BIT = 2;

    import smc_peripherals_tb_params_pkg::*;
    import axi4lite_vip_pkg::*;   // package-local AXI4-Lite VIP
    import smc_i3c_coverage_pkg::*;
    import smc_peripherals_ral_pkg::*;
`ifdef SMC_USE_I3C_RTL
    import i3c_vip_pkg::*;
`endif
`ifdef SMC_USE_I3C_RAL
    import I3CCSR_uvm::*;
`endif

    localparam string SMC_I3C_HOST_IBI_ARMED_EVENT =
      "smc_i3c_host_ibi_armed_event";
    localparam string SMC_I3C_HOST_IBI_DETECTED_EVENT =
      "smc_i3c_host_ibi_detected_event";
    localparam string SMC_I3C_TARGET_IBI_ARMED_EVENT =
      "smc_i3c_target_ibi_armed_event";
    localparam string SMC_I3C_TARGET_IBI_SLOT_ARMED_EVENT =
      "smc_i3c_target_ibi_slot_armed_event";

    `include "smc_i3c_csr_scoreboard_cfg.sv"
    `include "smc_peripherals_env_cfg.sv"
`ifdef SMC_USE_I3C_RTL
    `include "smc_i3c_monitor.sv"
    `include "smc_i3c_host_driver.sv"
    `include "smc_i3c_target_driver.sv"
`endif
    `include "smc_peripherals_vseq_services.sv"
    `include "smc_i3c_csr_access_seq.sv"
    `include "smc_i3c_csr_helper.sv"
`ifdef SMC_USE_I3C_RAL
    `include "smc_i3c_controller_hci_helper.sv"
`endif
`ifdef SMC_USE_I3C_RTL
`ifdef SMC_USE_I3C_RAL
    `include "smc_i3c_ibi_transaction.sv"
    `include "smc_i3c_ibi_recovery_checker.sv"
`endif
`endif
    `include "smc_peripherals_vseq_context.sv"
    `include "smc_peripherals_scoreboard.sv"
`ifdef SMC_USE_I3C_RTL
`ifdef SMC_USE_I3C_RAL
    `include "smc_i3c_ibi_sva_probe.sv"
    `include "smc_i3c_ibi_predictor.sv"
    `include "smc_i3c_ibi_observer.sv"
    `include "smc_i3c_ibi_scoreboard.sv"
    `include "smc_i3c_ibi_controller_predictor.sv"
    `include "smc_i3c_ibi_controller_observer.sv"
    `include "smc_i3c_ibi_controller_scoreboard.sv"
`endif
`endif
    `include "smc_peripherals_env.sv"
endpackage : smc_peripherals_env_pkg
