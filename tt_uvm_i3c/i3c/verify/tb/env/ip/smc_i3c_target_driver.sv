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
// File        : smc_i3c_target_driver.sv
// Description : UVM driver for I3C target.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-25
//
// *****************************************************************************

`ifndef SMC_I3C_TARGET_DRIVER_SV
`define SMC_I3C_TARGET_DRIVER_SV

class smc_i3c_target_ibi_observation extends uvm_sequence_item;
  longint unsigned transaction_id;
  longint unsigned source_sequence;
  bit [6:0] addr;
  bit ack;
  bit arbitration_won;
  bit released_after_loss;
  byte unsigned data[$];

  `uvm_object_utils_begin(smc_i3c_target_ibi_observation)
    `uvm_field_int(transaction_id, UVM_DEFAULT)
    `uvm_field_int(source_sequence, UVM_DEFAULT)
    `uvm_field_int(addr, UVM_DEFAULT)
    `uvm_field_int(ack, UVM_DEFAULT)
    `uvm_field_int(arbitration_won, UVM_DEFAULT)
    `uvm_field_int(released_after_loss, UVM_DEFAULT)
    `uvm_field_queue_int(data, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "smc_i3c_target_ibi_observation");
    super.new(name);
  endfunction
endclass : smc_i3c_target_ibi_observation

// Device-mode adapter for DUT-controller tests. It preserves the vendored
// I3C VIP driver and publishes the programmed target stimulus plus the ACK
// sampled from the resolved bus.
class smc_i3c_target_driver extends i3c_driver;
  `uvm_component_utils(smc_i3c_target_driver)

  uvm_analysis_port #(smc_i3c_target_ibi_observation) ibi_analysis_port;

  protected longint unsigned next_transaction_id = 1;
  protected longint unsigned next_source_sequence_by_addr[bit [6:0]];
  protected int unsigned target_slot;

  function new(string name = "smc_i3c_target_driver",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ibi_analysis_port = new("ibi_analysis_port", this);
    target_slot =
      (get_parent().get_name() == "i3c_agt_secondary") ? 1 : 0;
  endfunction

  static function void install_type_override();
    i3c_driver::type_id::set_type_override(smc_i3c_target_driver::get_type());
  endfunction

  // Keep the vendored VIP untouched while hardening its Device-mode request
  // lifetime for the SMC multi-target use case. The base implementation clears
  // rsp on every loop but leaves req pointing at the previous item. After a
  // completed arbitration, the STOP watcher can therefore re-arm from that
  // stale req while get_next_item() waits for a new sequence item. If it
  // observes the just-completed STOP again, it dereferences the null rsp.
  //
  // Reset req together with rsp, and do not arm the STOP/RStart watcher until
  // drive_device_item() has allocated the response for the current request.
  virtual task get_and_drive();
    i3c_seq_item req;
    i3c_seq_item rsp;

    @(posedge cfg.vif.rst_ni);
    forever begin
      release_bus();
      stop_b = 1'b0;
      rstart = 1'b0;
      req = null;
      rsp = null;

      fork
        begin : iso_fork
          fork
            begin
              seq_item_port.get_next_item(req);
              drive_device_item(req, rsp);
            end
            begin
              // req alone is insufficient: it may become visible before the
              // Device driver has allocated rsp. Both handles identify an
              // active request that can safely be terminated by STOP/RStart.
              wait((req != null) && (rsp != null));
              if (req.i3c)
                cfg.vif.wait_for_i3c_host_stop_or_rstart(
                  cfg.tc.i3c_tc, rstart, stop_b);
              else
                cfg.vif.wait_for_i2c_host_stop_or_rstart(
                  cfg.tc.i2c_tc, rstart, stop_b);
            end
            begin
              process_reset();
            end
            begin
              wait(cfg.driver_rst);
              `uvm_info(get_full_name(), "drvdbg agent reset", UVM_HIGH)
            end
          join_any
          disable fork;
        end : iso_fork
      join

      if (stop_b) begin
        `uvm_info(get_full_name(), "Device got Stop", UVM_HIGH)
        bus_state = DrvIdle;
        if (rsp != null)
          rsp.end_with_rstart = 1'b0;
      end
      else if (rstart) begin
        `uvm_info(get_full_name(), "Device got RStart", UVM_HIGH)
        bus_state = DrvAddr;
        if (rsp != null)
          rsp.end_with_rstart = 1'b1;
      end

      if (rsp != null) begin
        rsp.set_id_info(req);
        seq_item_port.item_done(rsp);
      end

      if (cfg.driver_rst) begin
        i3c_seq_item dummy;
        do begin
          seq_item_port.try_next_item(dummy);
          if (dummy != null)
            seq_item_port.item_done();
        end while (dummy != null);
      end
    end
  endtask : get_and_drive

  protected function void publish_ibi_observation(
      i3c_seq_item req,
      i3c_seq_item rsp);
    smc_i3c_target_ibi_observation observation;

    observation = smc_i3c_target_ibi_observation::type_id::create(
      "observation");
    observation.transaction_id = next_transaction_id++;
    observation.addr = req.IBI_ADDR;
    observation.ack = (rsp != null) ? rsp.dev_ack : 1'b0;
    observation.arbitration_won =
      (rsp != null) && (rsp.addr == req.IBI_ADDR) && rsp.dir;
    if (observation.arbitration_won) begin
      if (!next_source_sequence_by_addr.exists(req.IBI_ADDR))
        next_source_sequence_by_addr[req.IBI_ADDR] = 1;
      observation.source_sequence =
        next_source_sequence_by_addr[req.IBI_ADDR]++;
    end
    observation.released_after_loss =
      observation.arbitration_won ||
      ((cfg.vif.device_sda_o === 1'b1) &&
       (cfg.vif.device_sda_pp_en === 1'b0));
    foreach (req.data[i])
      observation.data.push_back(req.data[i]);
    ibi_analysis_port.write(observation);
  endfunction

  virtual task drive_device_item(i3c_seq_item req, ref i3c_seq_item rsp);
    uvm_event armed_event;
    bit is_ibi_address_phase;

    is_ibi_address_phase =
      (req != null) && req.IBI &&
      (bus_state inside {DrvIdle, DrvStart, DrvAddrArbit});
    if (is_ibi_address_phase && !req.IBI_START) begin
      armed_event = uvm_event_pool::get_global(
        SMC_I3C_TARGET_IBI_ARMED_EVENT);
      armed_event.trigger();
      armed_event = uvm_event_pool::get_global(
        $sformatf("%s_%0d", SMC_I3C_TARGET_IBI_SLOT_ARMED_EVENT,
                  target_slot));
      armed_event.trigger();
    end
    fork
      super.drive_device_item(req, rsp);
      begin
        if (is_ibi_address_phase) begin
          wait((rsp != null) &&
               (bus_state inside
                 {DrvAck, DrvSelectNext, DrvRdPushPull, DrvStop}));
          publish_ibi_observation(req, rsp);
        end
      end
    join
    if (is_ibi_address_phase && (rsp != null) &&
        !((rsp.addr == req.IBI_ADDR) && rsp.dir)) begin
      release_bus();
      bus_state = DrvIdle;
    end
  endtask
endclass : smc_i3c_target_driver

`endif // SMC_I3C_TARGET_DRIVER_SV
