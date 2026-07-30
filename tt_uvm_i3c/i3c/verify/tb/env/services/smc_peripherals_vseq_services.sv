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
// File        : smc_peripherals_vseq_services.sv
// Description : Runtime services for SMC peripheral virtual sequences.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-02
//
// *****************************************************************************

class smc_peripherals_vseq_services extends uvm_object;
    `uvm_object_utils(smc_peripherals_vseq_services)

    virtual smc_peripherals_if vif;

    function new(string name = "smc_peripherals_vseq_services");
        super.new(name);
    endfunction

    task wait_reset_release();
        if (vif == null) begin
            `uvm_fatal(get_type_name(), "smc_peripherals_vif is not configured")
        end
        @(posedge vif.rst_n);
        vif.mark_smoke_seen_reset_release();
    endtask
endclass : smc_peripherals_vseq_services
