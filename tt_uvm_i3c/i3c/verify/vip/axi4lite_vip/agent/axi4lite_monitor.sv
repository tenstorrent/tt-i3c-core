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
// File        : axi4lite_monitor.sv
// Description : Passive UVM monitor for AXI4-Lite transactions.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-28
//
// *****************************************************************************

`ifndef AXI4LITE_MONITOR_SV
`define AXI4LITE_MONITOR_SV

class axi4lite_monitor #(int ADDR_WIDTH = 32,
                         int DATA_WIDTH = 32) extends uvm_monitor;

  axi4lite_config #(ADDR_WIDTH, DATA_WIDTH) m_cfg;
  uvm_analysis_port #(axi4lite_item #(ADDR_WIDTH, DATA_WIDTH)) mon_analysis_port;

  bit [ADDR_WIDTH-1:0]     pending_awaddr;
  bit [DATA_WIDTH-1:0]     pending_wdata;
  bit [(DATA_WIDTH/8)-1:0] pending_wstrb;
  bit                      have_awaddr;
  bit                      have_wdata;
  bit [ADDR_WIDTH-1:0]     pending_araddr;
  bit                      have_araddr;

  `uvm_component_param_utils(axi4lite_monitor #(ADDR_WIDTH, DATA_WIDTH))

  function new(string name, uvm_component parent);
    super.new(name, parent);
    mon_analysis_port = new("mon_analysis_port", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(axi4lite_config #(ADDR_WIDTH, DATA_WIDTH))::get(this, "", "cfg", m_cfg)) begin
      `uvm_fatal("AXI4L_MON_CFG", "Missing axi4lite_config")
    end
    if (m_cfg.vif == null) begin
      `uvm_fatal("AXI4L_MON_VIF", "Monitor received a null virtual interface")
    end
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(posedge m_cfg.vif.clk);
      if (!m_cfg.vif.rst_n) begin
        have_awaddr = 1'b0; have_wdata = 1'b0; have_araddr = 1'b0;
        continue;
      end

      if (m_cfg.vif.awvalid && m_cfg.vif.awready) begin
        pending_awaddr = m_cfg.vif.awaddr; have_awaddr = 1'b1;
      end
      if (m_cfg.vif.wvalid && m_cfg.vif.wready) begin
        pending_wdata = m_cfg.vif.wdata; pending_wstrb = m_cfg.vif.wstrb; have_wdata = 1'b1;
      end
      if (m_cfg.vif.bvalid && m_cfg.vif.bready && have_awaddr && have_wdata) begin
        axi4lite_item #(ADDR_WIDTH, DATA_WIDTH) tr;
        tr = axi4lite_item #(ADDR_WIDTH, DATA_WIDTH)::type_id::create("write_tr", this);
        tr.addr = pending_awaddr; tr.write = 1'b1;
        tr.data = pending_wdata;  tr.strb = pending_wstrb; tr.resp = m_cfg.vif.bresp;
        mon_analysis_port.write(tr);
        have_awaddr = 1'b0; have_wdata = 1'b0;
      end

      if (m_cfg.vif.arvalid && m_cfg.vif.arready) begin
        pending_araddr = m_cfg.vif.araddr; have_araddr = 1'b1;
      end
      if (m_cfg.vif.rvalid && m_cfg.vif.rready && have_araddr) begin
        axi4lite_item #(ADDR_WIDTH, DATA_WIDTH) tr;
        tr = axi4lite_item #(ADDR_WIDTH, DATA_WIDTH)::type_id::create("read_tr", this);
        tr.addr = pending_araddr; tr.write = 1'b0;
        tr.rdata = m_cfg.vif.rdata; tr.resp = m_cfg.vif.rresp;
        mon_analysis_port.write(tr);
        have_araddr = 1'b0;
      end
    end
  endtask
endclass : axi4lite_monitor

`endif // AXI4LITE_MONITOR_SV
