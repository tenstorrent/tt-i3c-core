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
// File        : smc_i3c_csr_scoreboard_cfg.sv
// Description : Configuration object for I3C CSR scoreboard.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-16
//
// *****************************************************************************

class smc_i3c_csr_scoreboard_cfg #(int ADDR_WIDTH = TB_ADDR_WIDTH,
                                   int DATA_WIDTH = TB_DATA_WIDTH)
  extends uvm_object;

    `uvm_object_param_utils(smc_i3c_csr_scoreboard_cfg #(ADDR_WIDTH, DATA_WIDTH))

    virtual axi4lite_if #(ADDR_WIDTH, DATA_WIDTH) bus_vif;
    longint unsigned base_address = 'h0040_0000;
    longint unsigned window_bytes = 'h1000;

    function new(string name = "smc_i3c_csr_scoreboard_cfg");
        super.new(name);
    endfunction
endclass : smc_i3c_csr_scoreboard_cfg
