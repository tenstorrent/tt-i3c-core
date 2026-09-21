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
// File        : i3c_ral_all_regs_test.sv
// Description : UVM test for all I3C registers through the RAL model.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-16
//
// *****************************************************************************

class i3c_ral_all_regs_test extends i3c_base_test;
    `uvm_component_utils(i3c_ral_all_regs_test)

    function new(string name = "i3c_ral_all_regs_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function i3c_base_vseq create_vseq();
        return i3c_ral_all_regs_vseq::type_id::create("vseq");
    endfunction
endclass : i3c_ral_all_regs_test
