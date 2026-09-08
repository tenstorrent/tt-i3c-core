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
// File        : i3c_dv_monitor.sv
// Description : UVM monitor for I3C.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-24
//
// *****************************************************************************

`ifndef I3C_MONITOR_SV
`define I3C_MONITOR_SV

// Keeps the vendored I3C VIP monitor from dereferencing a null queue entry when
// a direct-CCC header is followed by STOP before any target phase is captured.
// A temporary queue item lets the original parser run without duplicating it.
class i3c_dv_monitor extends i3c_monitor;
  `uvm_component_utils(i3c_dv_monitor)

  function new(string name = "i3c_dv_monitor",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  static function void install_type_override();
    i3c_monitor::type_id::set_type_override(i3c_dv_monitor::get_type());
  endfunction

  // The base monitor drops its concurrent STOP watcher as soon as the final
  // device T-bit is sampled, then starts a new watcher. A Controller can issue
  // STOP in that gap, leaving the monitor blocked forever and withholding the
  // completed IBI transaction. Keep the original watcher alive until both the
  // final T-bit and the transfer boundary have been observed.
  virtual protected task ccc_data(
      i3c_item transaction,
      output i3c_item updated_transaction,
      input bit device_to_host,
      int count = -1,
      string msg = "Data byte");
    bit [8:0] sampled_data;
    bit data_done;
    bit bus_ended;

    if (!device_to_host || (count >= 0)) begin
      super.ccc_data(transaction, updated_transaction, device_to_host,
                     count, msg);
      return;
    end

    fork : i3c_device_to_host_capture
      begin
        forever begin
          for (int bit_index = 8; bit_index >= 0; bit_index--)
            cfg.vif.get_bit_data("device", sampled_data[bit_index]);
          transaction.data_q.push_back(sampled_data[8:1]);
          transaction.data_ack_q.push_back(sampled_data[0]);
          transaction.num_data++;
          `uvm_info(get_full_name(),
                    $sformatf("\nmonitor, %s, trans %0d, 0x%0x",
                              msg, transaction.tran_id,
                              sampled_data[8:1]),
                    UVM_HIGH)
          if (!sampled_data[0]) begin
            data_done = 1'b1;
            break;
          end
        end
      end
      begin
        cfg.vif.wait_for_i3c_host_stop_or_rstart(
          cfg.tc.i3c_tc, transaction.rstart, transaction.stop);
        bus_ended = 1'b1;
      end
    join_any

    if (data_done && !bus_ended)
      wait (bus_ended);
    disable i3c_device_to_host_capture;
    updated_transaction = transaction;
  endtask : ccc_data

  virtual protected task i3c_direct(ref i3c_item transaction);
    i3c_item guard_item;
    bit guard_inserted;

    if (transaction.CCC_direct.size() == 0) begin
      guard_inserted = 1'b1;
    end else if (transaction.CCC_direct[$] == null) begin
      guard_item = transaction.CCC_direct.pop_back();
      guard_inserted = 1'b1;
    end

    if (guard_inserted) begin
      guard_item = new;
      transaction.CCC_direct.push_back(guard_item);
    end

    super.i3c_direct(transaction);

    if (guard_inserted) begin
      foreach (transaction.CCC_direct[i]) begin
        if (transaction.CCC_direct[i] == guard_item) begin
          transaction.CCC_direct.delete(i);
          break;
        end
      end
      if (guard_item.stop)
        `uvm_warning("I3C_MON_EMPTY_DIRECT",
                     {"direct CCC ended before a target phase; ",
                      "ignored the empty queue entry from the base VIP"})
    end
  endtask : i3c_direct
endclass : i3c_dv_monitor

`endif // I3C_MONITOR_SV
