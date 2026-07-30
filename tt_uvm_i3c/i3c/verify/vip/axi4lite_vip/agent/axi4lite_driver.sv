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
// File        : axi4lite_driver.sv
// Description : UVM master driver for AXI4-Lite transactions.
// Authors     : Dang Thai
// Date        : 2026-07-28
//
// *****************************************************************************

`ifndef AXI4LITE_DRIVER_SV
`define AXI4LITE_DRIVER_SV

class axi4lite_driver #(int ADDR_WIDTH = 32,
                        int DATA_WIDTH = 32)
  extends uvm_driver #(axi4lite_item #(ADDR_WIDTH, DATA_WIDTH));

  axi4lite_config #(ADDR_WIDTH, DATA_WIDTH) m_cfg;

  `uvm_component_param_utils(axi4lite_driver #(ADDR_WIDTH, DATA_WIDTH))

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(axi4lite_config #(ADDR_WIDTH, DATA_WIDTH))::get(this, "", "cfg", m_cfg)) begin
      `uvm_fatal("AXI4L_DRV_CFG", "Missing axi4lite_config")
    end
    if (m_cfg.vif == null) begin
      `uvm_fatal("AXI4L_DRV_VIF", "Driver received a null virtual interface")
    end
  endfunction

  task run_phase(uvm_phase phase);
    axi4lite_item #(ADDR_WIDTH, DATA_WIDTH) req;
    reset_master();
    forever begin
      seq_item_port.get_next_item(req);
      if (req.write) drive_write(req);
      else           drive_read(req);
      seq_item_port.item_done();
    end
  endtask

  task reset_master();
    m_cfg.vif.awaddr  <= '0;
    m_cfg.vif.awvalid <= 1'b0;
    m_cfg.vif.wdata   <= '0;
    m_cfg.vif.wstrb   <= '0;
    m_cfg.vif.wvalid  <= 1'b0;
    m_cfg.vif.bready  <= 1'b0;
    m_cfg.vif.araddr  <= '0;
    m_cfg.vif.arvalid <= 1'b0;
    m_cfg.vif.rready  <= 1'b0;
  endtask

  task wait_for_reset_release();
    while (m_cfg.vif.rst_n !== 1'b1) begin
      @(posedge m_cfg.vif.clk);
      reset_master();
    end
  endtask

  task drive_write(axi4lite_item #(ADDR_WIDTH, DATA_WIDTH) req);
    bit aw_done, w_done;
    wait_for_reset_release();
    @(posedge m_cfg.vif.clk);
    m_cfg.vif.awaddr  <= req.addr;
    m_cfg.vif.awvalid <= 1'b1;
    m_cfg.vif.wdata   <= req.data;
    m_cfg.vif.wstrb   <= req.strb;
    m_cfg.vif.wvalid  <= 1'b1;
    m_cfg.vif.bready  <= 1'b1;
    aw_done = 1'b0;
    w_done  = 1'b0;

    do begin
      @(posedge m_cfg.vif.clk);
      if (!aw_done && m_cfg.vif.awvalid && m_cfg.vif.awready) begin
        m_cfg.vif.awvalid <= 1'b0; m_cfg.vif.awaddr <= '0; aw_done = 1'b1;
      end
      if (!w_done && m_cfg.vif.wvalid && m_cfg.vif.wready) begin
        m_cfg.vif.wvalid <= 1'b0; m_cfg.vif.wdata <= '0; m_cfg.vif.wstrb <= '0; w_done = 1'b1;
      end
    end while (!(aw_done && w_done));

    do @(posedge m_cfg.vif.clk); while (!m_cfg.vif.bvalid);
    req.resp = m_cfg.vif.bresp;
    @(posedge m_cfg.vif.clk);
    m_cfg.vif.bready <= 1'b0;
  endtask

  task drive_read(axi4lite_item #(ADDR_WIDTH, DATA_WIDTH) req);
    wait_for_reset_release();
    @(posedge m_cfg.vif.clk);
    m_cfg.vif.araddr  <= req.addr;
    m_cfg.vif.arvalid <= 1'b1;
    m_cfg.vif.rready  <= 1'b1;

    do @(posedge m_cfg.vif.clk); while (!m_cfg.vif.arready);
    m_cfg.vif.arvalid <= 1'b0;
    m_cfg.vif.araddr  <= '0;

    do @(posedge m_cfg.vif.clk); while (!m_cfg.vif.rvalid);
    req.rdata = m_cfg.vif.rdata;
    req.resp  = m_cfg.vif.rresp;
    @(posedge m_cfg.vif.clk);
    m_cfg.vif.rready <= 1'b0;
  endtask
endclass : axi4lite_driver

`endif // AXI4LITE_DRIVER_SV
