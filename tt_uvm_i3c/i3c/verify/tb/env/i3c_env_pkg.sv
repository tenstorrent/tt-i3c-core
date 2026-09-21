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
// File        : i3c_env_pkg.sv
// Description : UVM environment package for I3C verification environment.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-06
//
// *****************************************************************************

package i3c_env_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // BCR IBI capability bits shared by Controller reference checking and
    // IBI scenario construction.  Keep the values aligned with the existing
    // base IBI vseq contract.
    localparam int unsigned I3C_BCR_IBI_CAPABLE_BIT = 1;
    localparam int unsigned I3C_BCR_MDB_CAPABLE_BIT = 2;

    import i3c_tb_params_pkg::*;
    import axi4lite_vip_pkg::*;   // package-local AXI4-Lite VIP
    import i3c_coverage_pkg::*;
    import i3c_ral_pkg::*;
`ifdef I3C_DV_NATIVE_RTL
    import i3c_vip_pkg::*;
`endif
`ifdef I3C_DV_NATIVE_RAL
    import I3CCSR_uvm::*;
`endif

    localparam string I3C_HOST_IBI_ARMED_EVENT =
      "i3c_host_ibi_armed_event";
    localparam string I3C_HOST_IBI_DETECTED_EVENT =
      "i3c_host_ibi_detected_event";
    localparam string I3C_TARGET_IBI_ARMED_EVENT =
      "i3c_target_ibi_armed_event";
    localparam string I3C_TARGET_IBI_SLOT_ARMED_EVENT =
      "i3c_target_ibi_slot_armed_event";

    `include "i3c_csr_scoreboard_cfg.sv"
    `include "i3c_env_cfg.sv"
`ifdef I3C_DV_NATIVE_RTL
    `include "i3c_dv_monitor.sv"
    `include "i3c_dv_host_driver.sv"
    `include "i3c_dv_target_driver.sv"
`endif
    `include "i3c_vseq_services.sv"
    `include "i3c_csr_access_seq.sv"
    `include "i3c_csr_helper.sv"
`ifdef I3C_DV_NATIVE_RAL
    `include "i3c_controller_hci_helper.sv"
`endif
`ifdef I3C_DV_NATIVE_RTL
`ifdef I3C_DV_NATIVE_RAL
    `include "i3c_ibi_transaction.sv"
    `include "i3c_ibi_recovery_checker.sv"
`endif
`endif
    `include "i3c_vseq_context.sv"
    `include "i3c_scoreboard.sv"
`ifdef I3C_DV_NATIVE_RTL
`ifdef I3C_DV_NATIVE_RAL
    `include "i3c_ibi_sva_probe.sv"
    `include "i3c_ibi_predictor.sv"
    `include "i3c_ibi_observer.sv"
    `include "i3c_ibi_scoreboard.sv"
    `include "i3c_ibi_controller_predictor.sv"
    `include "i3c_ibi_controller_observer.sv"
    `include "i3c_ibi_controller_scoreboard.sv"
`endif
`endif
    `include "i3c_env.sv"
endpackage : i3c_env_pkg
