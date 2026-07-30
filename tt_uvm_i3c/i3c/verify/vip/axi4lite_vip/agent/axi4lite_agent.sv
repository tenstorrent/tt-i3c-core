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
// File        : axi4lite_agent.sv
// Description : Active/passive UVM agent for AXI4-Lite.
// Authors     : Dang Thai
// Date        : 2026-07-28
//
// *****************************************************************************

`ifndef AXI4LITE_AGENT_SV
`define AXI4LITE_AGENT_SV

class axi4lite_agent #(int ADDR_WIDTH = 32,
                       int DATA_WIDTH = 32) extends uvm_agent;

  axi4lite_config    #(ADDR_WIDTH, DATA_WIDTH) m_cfg;
  axi4lite_sequencer #(ADDR_WIDTH, DATA_WIDTH) sqr;
  axi4lite_driver    #(ADDR_WIDTH, DATA_WIDTH) drv;
  axi4lite_monitor   #(ADDR_WIDTH, DATA_WIDTH) mon;
  uvm_analysis_port  #(axi4lite_item #(ADDR_WIDTH, DATA_WIDTH)) mon_analysis_port;

  `uvm_component_param_utils(axi4lite_agent #(ADDR_WIDTH, DATA_WIDTH))

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(axi4lite_config #(ADDR_WIDTH, DATA_WIDTH))::get(this, "", "cfg", m_cfg)) begin
      `uvm_fatal("AXI4L_AGENT_CFG", "Missing axi4lite_config")
    end

    uvm_config_db#(axi4lite_config #(ADDR_WIDTH, DATA_WIDTH))::set(this, "mon", "cfg", m_cfg);
    mon = axi4lite_monitor #(ADDR_WIDTH, DATA_WIDTH)::type_id::create("mon", this);

    if (m_cfg.is_active == UVM_ACTIVE) begin
      uvm_config_db#(axi4lite_config #(ADDR_WIDTH, DATA_WIDTH))::set(this, "drv", "cfg", m_cfg);
      sqr = axi4lite_sequencer #(ADDR_WIDTH, DATA_WIDTH)::type_id::create("sqr", this);
      drv = axi4lite_driver    #(ADDR_WIDTH, DATA_WIDTH)::type_id::create("drv", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    mon_analysis_port = mon.mon_analysis_port;
    if (m_cfg.is_active == UVM_ACTIVE) begin
      drv.seq_item_port.connect(sqr.seq_item_export);
    end
  endfunction
endclass : axi4lite_agent

`endif // AXI4LITE_AGENT_SV
