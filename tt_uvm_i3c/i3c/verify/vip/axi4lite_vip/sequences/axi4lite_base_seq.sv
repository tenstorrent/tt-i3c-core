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
// File        : axi4lite_base_seq.sv
// Description : Base AXI4-Lite sequence with read/write helpers.
// Authors     : Dang Thai
// Date        : 2026-07-28
//
// *****************************************************************************

`ifndef AXI4LITE_BASE_SEQ_SV
`define AXI4LITE_BASE_SEQ_SV

class axi4lite_base_seq #(int ADDR_WIDTH = 32,
                          int DATA_WIDTH = 32)
  extends uvm_sequence #(axi4lite_item #(ADDR_WIDTH, DATA_WIDTH));

  `uvm_object_param_utils(axi4lite_base_seq #(ADDR_WIDTH, DATA_WIDTH))

  function new(string name = "axi4lite_base_seq");
    super.new(name);
  endfunction

  task write(input bit [ADDR_WIDTH-1:0] addr,
             input bit [DATA_WIDTH-1:0] data,
             input bit [(DATA_WIDTH/8)-1:0] strb = {(DATA_WIDTH/8){1'b1}},
             output bit [1:0] resp);
    axi4lite_item #(ADDR_WIDTH, DATA_WIDTH) tr;
    tr = axi4lite_item #(ADDR_WIDTH, DATA_WIDTH)::type_id::create("wr");
    start_item(tr);
    tr.addr = addr; tr.write = 1'b1; tr.data = data; tr.strb = strb;
    finish_item(tr);
    resp = tr.resp;
  endtask

  task read(input  bit [ADDR_WIDTH-1:0] addr,
            output bit [DATA_WIDTH-1:0] data,
            output bit [1:0]            resp);
    axi4lite_item #(ADDR_WIDTH, DATA_WIDTH) tr;
    tr = axi4lite_item #(ADDR_WIDTH, DATA_WIDTH)::type_id::create("rd");
    start_item(tr);
    tr.addr = addr; tr.write = 1'b0;
    finish_item(tr);
    data = tr.rdata; resp = tr.resp;
  endtask
endclass : axi4lite_base_seq

`endif // AXI4LITE_BASE_SEQ_SV
