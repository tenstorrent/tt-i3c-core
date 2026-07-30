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
// Description : UVM package for I3C coverage.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-20
//
// *****************************************************************************

package smc_i3c_coverage_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import smc_peripherals_tb_params_pkg::*;
    import axi4lite_vip_pkg::*;

    // IBI monitor transaction (event-kinded) + domain-split IBI coverage.
    `include "smc_i3c_ibi_item.sv"
    `include "internal/smc_i3c_ibi_attempt_coverage.sv"
    `include "internal/smc_i3c_ibi_completion_coverage.sv"
    `include "ip/smc_i3c_ibi_queue_irq_coverage.sv"
    `include "integration/smc_i3c_ibi_coverage.sv"

    class smc_i3c_integration_coverage extends
      uvm_subscriber #(axi4lite_item #(TB_ADDR_WIDTH, TB_DATA_WIDTH));
        `uvm_component_utils(smc_i3c_integration_coverage)

        bit [TB_ADDR_WIDTH-1:0] sampled_addr;
        bit sampled_write;
        bit [1:0] sampled_resp;

        covergroup i3c_access_cg;
            option.per_instance = 1;
            cp_window: coverpoint sampled_addr {
                bins hci_csr = {[32'h0040_0000:32'h0040_0fff]};
                bins below   = {[32'h0000_0000:32'h003f_ffff]};
                bins above   = {[32'h0040_1000:32'hffff_ffff]};
            }
            cp_access: coverpoint sampled_write {
                bins read = {0};
                bins write = {1};
            }
            cp_response: coverpoint sampled_resp {
                bins okay = {2'b00};
                bins slverr = {2'b10};
                bins decerr = {2'b11};
            }
            access_response: cross cp_access, cp_response;
        endgroup

        function new(string name = "smc_i3c_integration_coverage",
                     uvm_component parent = null);
            super.new(name, parent);
            i3c_access_cg = new();
        endfunction

        virtual function void write(
          axi4lite_item #(TB_ADDR_WIDTH, TB_DATA_WIDTH) t);
            sampled_addr = t.addr;
            sampled_write = t.write;
            sampled_resp = t.resp;
            i3c_access_cg.sample();
        endfunction
    endclass : smc_i3c_integration_coverage
endpackage : smc_i3c_coverage_pkg
