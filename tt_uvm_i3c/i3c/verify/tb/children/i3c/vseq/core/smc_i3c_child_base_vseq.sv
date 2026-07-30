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
// File        : smc_i3c_child_base_vseq.sv
// Description : Base virtual sequence for the portable I3C child environment.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-14
//
// *****************************************************************************

class smc_i3c_child_base_vseq extends uvm_sequence;
    `uvm_object_utils(smc_i3c_child_base_vseq)
    smc_i3c_child_context context;
    function new(string name = "smc_i3c_child_base_vseq");
        super.new(name);
    endfunction
    protected function void require_context();
        if (context == null || context.csr_api == null)
            `uvm_fatal(get_type_name(), "Portable I3C context/API is not configured")
    endfunction
endclass : smc_i3c_child_base_vseq
