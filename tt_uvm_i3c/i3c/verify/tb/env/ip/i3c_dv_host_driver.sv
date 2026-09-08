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
// File        : i3c_dv_host_driver.sv
// Description : UVM driver for I3C host.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-24
//
// *****************************************************************************

`ifndef I3C_HOST_DRIVER_SV
`define I3C_HOST_DRIVER_SV

class i3c_host_ibi_observation extends uvm_sequence_item;
  bit [6:0] addr;
  bit ack;
  byte unsigned data[$];

  `uvm_object_utils_begin(i3c_host_ibi_observation)
    `uvm_field_int(addr, UVM_DEFAULT)
    `uvm_field_int(ack, UVM_DEFAULT)
    `uvm_field_queue_int(data, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "i3c_host_ibi_observation");
    super.new(name);
  endfunction
endclass : i3c_host_ibi_observation

// Adds testbench-only IBI synchronization and I3C ownership-handoff fixes
// without modifying the vendored I3C VIP driver. The base host waits for SCL to
// fall before taking SDA at both address-ACK and read-termination boundaries.
// The previous owner releases during SCL high, so either uncovered interval
// otherwise appears as a false STOP on the resolved bus.
class i3c_dv_host_driver extends i3c_driver;
  `uvm_component_utils(i3c_dv_host_driver)

  uvm_analysis_port #(i3c_host_ibi_observation) ibi_analysis_port;

  function new(string name = "i3c_dv_host_driver",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ibi_analysis_port = new("ibi_analysis_port", this);
  endfunction

  static function void install_type_override();
    i3c_driver::type_id::set_type_override(i3c_dv_host_driver::get_type());
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
      `uvm_info("I3C_ACK_HANDOFF",
                "Held SDA low across the target-ACK to host-data handoff",
                UVM_HIGH)
      @(negedge cfg.vif.scl_i);
    end
  endtask

  // During an I3C Read, the Target drives the T-bit. For a terminal T-bit of
  // zero, the Controller must take over the same low level after sampling it
  // and retain it through the following STOP. Waiting for SCL low is too late:
  // the Target is permitted to release after the T-bit rising edge, which
  // would create an unintended STOP while SCL is still high.
  protected task hold_read_end_handoff(input int unsigned max_data_bytes);
    // The continuation first emits the Controller's IBI ACK clock.
    @(posedge cfg.vif.scl_i);

    for (int unsigned byte_index = 0;
         byte_index < max_data_bytes; byte_index++) begin
      // Eight data clocks followed by the Target-owned T-bit clock.
      repeat (9)
        @(posedge cfg.vif.scl_i);
      if (cfg.vif.sda_i === 1'b0) begin
        cfg.vif.host_sda_pp_en = 1'b0;
        cfg.vif.host_sda_o = 1'b0;
        `uvm_info("I3C_READ_END_HANDOFF",
                  "Held terminal T-bit low through Controller STOP handoff",
                  UVM_HIGH)
        return;
      end
    end
  endtask

  protected function void publish_ibi_observation(
    i3c_seq_item req,
    i3c_seq_item rsp
  );
    i3c_host_ibi_observation observation;

    observation = i3c_host_ibi_observation::type_id::create(
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
      armed_event = uvm_event_pool::get_global(I3C_HOST_IBI_ARMED_EVENT);
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
        I3C_HOST_IBI_DETECTED_EVENT);
      detected_event.trigger();

      // The base driver returns after address arbitration. Continue the same
      // request through ACK, data reception, and STOP before responding. Arm
      // the Controller handoff in parallel so a terminal Target T-bit cannot
      // be released into a false physical STOP.
      fork : read_end_handoff_guard
        hold_read_end_handoff(req.data_cnt);
      join_none
      super.drive_host_item(req, transfer_rsp);
      disable read_end_handoff_guard;
      if (transfer_rsp == null)
        `uvm_fatal("I3C_IBI_CONTINUE",
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
endclass : i3c_dv_host_driver

`endif // I3C_HOST_DRIVER_SV
