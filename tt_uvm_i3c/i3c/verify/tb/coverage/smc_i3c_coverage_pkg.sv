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
// File        : smc_i3c_coverage_pkg.sv
// Description : UVM package for I3C IBI coverage.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-06
//
// *****************************************************************************

package smc_i3c_coverage_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import smc_peripherals_tb_params_pkg::*;
`ifdef SMC_USE_I3C_RTL
    import i3c_vip_pkg::*;
`endif

    // IBI monitor transaction (event-kinded) + domain-split IBI coverage.
    `include "smc_i3c_ibi_item.sv"
    `include "internal/smc_i3c_ibi_attempt_coverage.sv"
    `include "internal/smc_i3c_ibi_completion_coverage.sv"
    `include "internal/smc_i3c_ibi_recovery_coverage.sv"
    `include "ip/smc_i3c_ibi_queue_irq_coverage.sv"
    `include "integration/smc_i3c_ibi_coverage.sv"
    `include "integration/smc_i3c_ibi_blocked_coverage.sv"
endpackage : smc_i3c_coverage_pkg
