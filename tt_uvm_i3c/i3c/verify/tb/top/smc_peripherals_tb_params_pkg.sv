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
// File        : smc_peripherals_tb_params_pkg.sv
// Description : Testbench parameters for the SMC peripheral environment.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-24
//
// *****************************************************************************

package smc_peripherals_tb_params_pkg;
    parameter int TB_CLK_HALF_NS      = 5;
    parameter int TB_RESET_ASSERT_NS  = 20;
    parameter int TB_ADDR_WIDTH       = 32;
    parameter int TB_DATA_WIDTH       = 32;
    parameter int TB_NUM_I3C_INSTANCES = 1;
    parameter int TB_MAX_I3C_INSTANCES = 6;
    // Verification capacity for one DUT/UVM primary requester plus up to
    // three additional UVM Targets on the shared open-drain bus.
    parameter int TB_MAX_IBI_REQUESTERS = 4;
    parameter bit [6:0] TB_DEFAULT_IBI_TARGET_ADDR = 7'h5a;
    parameter int TB_GPIO_WIDTH       = 68;
    parameter int TB_OTP_ADDR_WIDTH   = 16;
    parameter int TB_OTP_DATA_WIDTH   = 32;
    parameter int TB_PLL_COUNT        = 4;
    parameter int TB_PVT_COUNT        = 4;
endpackage : smc_peripherals_tb_params_pkg
