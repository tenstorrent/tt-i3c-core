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
// File        : axi4lite_sequencer.sv
// Description : UVM sequencer for AXI4-Lite transactions.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-28
//
// *****************************************************************************

`ifndef AXI4LITE_SEQUENCER_SV
`define AXI4LITE_SEQUENCER_SV

class axi4lite_sequencer #(int ADDR_WIDTH = 32,
                           int DATA_WIDTH = 32)
  extends uvm_sequencer #(axi4lite_item #(ADDR_WIDTH, DATA_WIDTH));

  `uvm_component_param_utils(axi4lite_sequencer #(ADDR_WIDTH, DATA_WIDTH))

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass : axi4lite_sequencer

`endif // AXI4LITE_SEQUENCER_SV
