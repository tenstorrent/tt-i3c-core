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
// File        : smc_peripherals_ral_pkg.sv
// Description : UVM package for peripherals RAL.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-18
//
// *****************************************************************************

package smc_peripherals_ral_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import smc_peripherals_tb_params_pkg::*;
    import axi4lite_vip_pkg::*;

`ifdef SMC_USE_I3C_RAL
    import I3CCSR_uvm::*;
    `include "smc_i3c_ral_model.sv"
    `include "axi4lite_reg_adapter.sv"
`endif
endpackage : smc_peripherals_ral_pkg
