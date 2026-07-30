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
// File        : smc_i3c_host_driver.sv
// Description : UVM driver for I3C host.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-24
//
// *****************************************************************************

`ifndef SMC_I3C_HOST_DRIVER_SV
`define SMC_I3C_HOST_DRIVER_SV

class smc_i3c_host_ibi_observation extends uvm_sequence_item;
  bit [6:0] addr;
  bit ack;
  byte unsigned data[$];

  `uvm_object_utils_begin(smc_i3c_host_ibi_observation)
    `uvm_field_int(addr, UVM_DEFAULT)
    `uvm_field_int(ack, UVM_DEFAULT)
    `uvm_field_queue_int(data, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "smc_i3c_host_ibi_observation");
    super.new(name);
  endfunction
endclass : smc_i3c_host_ibi_observation

// Adds testbench-only IBI synchronization and an I3C address-ACK handoff fix
// without modifying the vendored I3C VIP driver. The base host waits for SCL to
// fall before driving the first data bit; the DUT target releases its ACK
// during SCL high, so the uncovered interval otherwise appears as a STOP.
class smc_i3c_host_driver extends i3c_driver;
  `uvm_component_utils(smc_i3c_host_driver)

  uvm_analysis_port #(smc_i3c_host_ibi_observation) ibi_analysis_port;

  function new(string name = "smc_i3c_host_driver",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ibi_analysis_port = new("ibi_analysis_port", this);
  endfunction

  static function void install_type_override();
    i3c_driver::type_id::set_type_override(smc_i3c_host_driver::get_type());
  endfunction

  protected function bit needs_address_ack_handoff(i3c_seq_item req);
    return req.i3c && !req.IBI && !req.dir && req.dev_ack;
  endfunction

  protected task hold_address_ack_handoff();
    cfg.vif.wait_for_host_start();
    repeat (8)
      @(posedge cfg.vif.scl_i);
    @(posedge cfg.vif.scl_i);

    if (cfg.vif.sda_i === 1'b0) begin
      // The controller owns SDA after sampling the target ACK. Hold the low
      // level until the upstream driver starts the first host data bit.
      cfg.vif.host_sda_o = 1'b0;
      `uvm_info("SMC_I3C_ACK_HANDOFF",
                "Held SDA low across the target-ACK to host-data handoff",
                UVM_HIGH)
      @(negedge cfg.vif.scl_i);
    end
  endtask

  protected function void publish_ibi_observation(
    i3c_seq_item req,
    i3c_seq_item rsp
  );
    smc_i3c_host_ibi_observation observation;

    observation = smc_i3c_host_ibi_observation::type_id::create(
      "observation");
    observation.addr = rsp.IBI_ADDR;
    observation.ack = req.IBI_ACK;
    foreach (rsp.data[i])
      observation.data.push_back(rsp.data[i]);
    ibi_analysis_port.write(observation);
  endfunction

  virtual task drive_host_item(i3c_seq_item req, ref i3c_seq_item rsp);
    uvm_event armed_event;
    uvm_event detected_event;
    i3c_seq_item address_rsp;
    i3c_seq_item transfer_rsp;
    bit [6:0] ibi_addr;

    if (req.IBI && req.IBI_START) begin
      armed_event = uvm_event_pool::get_global(SMC_I3C_HOST_IBI_ARMED_EVENT);
      armed_event.trigger();
    end

    if (needs_address_ack_handoff(req)) begin
      fork : address_ack_handoff_guard
        hold_address_ack_handoff();
      join_none
      super.drive_host_item(req, address_rsp);
      disable address_ack_handoff_guard;
    end else begin
      super.drive_host_item(req, address_rsp);
    end

    if (req.IBI && req.IBI_START &&
        (address_rsp != null) && address_rsp.IBI) begin
      ibi_addr = address_rsp.IBI_ADDR;
      detected_event = uvm_event_pool::get_global(
        SMC_I3C_HOST_IBI_DETECTED_EVENT);
      detected_event.trigger();

      // The base driver returns after address arbitration. Continue the
      // same request through ACK, data reception, and STOP before responding.
      super.drive_host_item(req, transfer_rsp);
      if (transfer_rsp == null)
        `uvm_fatal("SMC_I3C_IBI_CONTINUE",
                   "IBI continuation returned no response")

      transfer_rsp.IBI = 1'b1;
      transfer_rsp.IBI_ADDR = ibi_addr;
      rsp = transfer_rsp;
    end else begin
      rsp = address_rsp;
    end

    if ((rsp != null) && rsp.IBI)
      publish_ibi_observation(req, rsp);
  endtask
endclass : smc_i3c_host_driver

`endif // SMC_I3C_HOST_DRIVER_SV
