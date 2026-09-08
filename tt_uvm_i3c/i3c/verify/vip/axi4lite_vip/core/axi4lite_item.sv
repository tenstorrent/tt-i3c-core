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
// File        : axi4lite_item.sv
// Description : AXI4-Lite read/write transaction item.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-28
//
// *****************************************************************************

`ifndef AXI4LITE_ITEM_SV
`define AXI4LITE_ITEM_SV

class axi4lite_item #(int ADDR_WIDTH = 32,
                      int DATA_WIDTH = 32) extends uvm_sequence_item;

  rand bit [ADDR_WIDTH-1:0]     addr;
  rand bit                      write;
  rand bit [DATA_WIDTH-1:0]     data;
  rand bit [(DATA_WIDTH/8)-1:0] strb;

  bit [DATA_WIDTH-1:0]          rdata;
  bit [1:0]                     resp;

  `uvm_object_param_utils(axi4lite_item #(ADDR_WIDTH, DATA_WIDTH))

  function new(string name = "axi4lite_item");
    super.new(name);
    strb = {(DATA_WIDTH/8){1'b1}};
  endfunction

  function string convert2string();
    return $sformatf("addr=0x%0h write=%0b data=0x%0h rdata=0x%0h strb=0x%0h resp=0x%0h",
                     addr, write, data, rdata, strb, resp);
  endfunction
endclass : axi4lite_item

`endif // AXI4LITE_ITEM_SV
