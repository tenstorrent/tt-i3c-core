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
// File        : smc_i3c_boundary_item.sv
// Description : UVM transaction item for I3C boundary.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-14
//
// *****************************************************************************

class smc_i3c_boundary_item extends uvm_sequence_item;
    `uvm_object_utils(smc_i3c_boundary_item)
    bit [31:0] offset;
    bit write;
    bit [31:0] data;
    bit [1:0] response;
    function new(string name = "smc_i3c_boundary_item");
        super.new(name);
    endfunction
endclass : smc_i3c_boundary_item
