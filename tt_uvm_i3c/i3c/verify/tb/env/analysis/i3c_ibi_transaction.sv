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
// File        : i3c_ibi_transaction.sv
// Description : Transaction models for I3C IBI.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-25
//
// *****************************************************************************

`ifndef I3C_IBI_TRANSACTION_SV
`define I3C_IBI_TRANSACTION_SV

// source_instance + target_addr + source_sequence is the cross-component
// correlation key. transaction_id remains local provenance for diagnostics.
class i3c_ibi_expected_item extends uvm_sequence_item;
  longint unsigned transaction_id;
  bit [2:0] source_instance;
  bit [6:0] target_addr;
  longint unsigned source_sequence;
  bit mdb_present;
  bit [7:0] mdb;
  bit [2:0] expected_status_type;
  int unsigned payload_len;
  byte unsigned payload[$];
  bit expected_ack;
  ibi_terminal_status_e expected_terminal_status;
  bit dat_match;
  bit [1:0] payload_policy;
  bit ibi_enabled;
  bit irq_enabled_at_attempt;
  bit irq_asserted_at_attempt;
  bit queue_full_reject;

  `uvm_object_utils_begin(i3c_ibi_expected_item)
    `uvm_field_int(transaction_id, UVM_DEFAULT)
    `uvm_field_int(source_instance, UVM_DEFAULT)
    `uvm_field_int(target_addr, UVM_DEFAULT)
    `uvm_field_int(source_sequence, UVM_DEFAULT)
    `uvm_field_int(mdb_present, UVM_DEFAULT)
    `uvm_field_int(mdb, UVM_DEFAULT)
    `uvm_field_int(expected_status_type, UVM_DEFAULT)
    `uvm_field_int(payload_len, UVM_DEFAULT)
    `uvm_field_queue_int(payload, UVM_DEFAULT)
    `uvm_field_int(expected_ack, UVM_DEFAULT)
    `uvm_field_enum(ibi_terminal_status_e, expected_terminal_status,
                    UVM_DEFAULT)
    `uvm_field_int(dat_match, UVM_DEFAULT)
    `uvm_field_int(payload_policy, UVM_DEFAULT)
    `uvm_field_int(ibi_enabled, UVM_DEFAULT)
    `uvm_field_int(irq_enabled_at_attempt, UVM_DEFAULT)
    `uvm_field_int(irq_asserted_at_attempt, UVM_DEFAULT)
    `uvm_field_int(queue_full_reject, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "i3c_ibi_expected_item");
    super.new(name);
  endfunction
endclass : i3c_ibi_expected_item

class i3c_ibi_actual_item extends uvm_sequence_item;
  longint unsigned transaction_id;
  bit [2:0] source_instance;
  longint unsigned source_sequence;
  bit [6:0] addr;
  bit ack;
  int unsigned retry_count;
  byte unsigned data[$];
  bit irq_seen;
  bit status_seen;
  ibi_terminal_status_e terminal_status;
  bit passive_seen;
  bit passive_ack;
  byte unsigned passive_data[$];
  bit ibi_enabled_at_attempt;
  bit attempt_context_valid;

  `uvm_object_utils_begin(i3c_ibi_actual_item)
    `uvm_field_int(transaction_id, UVM_DEFAULT)
    `uvm_field_int(source_instance, UVM_DEFAULT)
    `uvm_field_int(source_sequence, UVM_DEFAULT)
    `uvm_field_int(addr, UVM_DEFAULT)
    `uvm_field_int(ack, UVM_DEFAULT)
    `uvm_field_int(retry_count, UVM_DEFAULT)
    `uvm_field_queue_int(data, UVM_DEFAULT)
    `uvm_field_int(irq_seen, UVM_DEFAULT)
    `uvm_field_int(status_seen, UVM_DEFAULT)
    `uvm_field_enum(ibi_terminal_status_e, terminal_status, UVM_DEFAULT)
    `uvm_field_int(passive_seen, UVM_DEFAULT)
    `uvm_field_int(passive_ack, UVM_DEFAULT)
    `uvm_field_queue_int(passive_data, UVM_DEFAULT)
    `uvm_field_int(ibi_enabled_at_attempt, UVM_DEFAULT)
    `uvm_field_int(attempt_context_valid, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "i3c_ibi_actual_item");
    super.new(name);
  endfunction
endclass : i3c_ibi_actual_item

class i3c_ibi_passive_item;
  bit [6:0] addr;
  longint unsigned source_sequence;
  bit ack;
  byte unsigned data[$];
endclass : i3c_ibi_passive_item

class i3c_ibi_controller_actual_item extends uvm_sequence_item;
  longint unsigned transaction_id;
  bit [2:0] source_instance;
  longint unsigned source_sequence;
  bit [6:0] addr;
  bit target_seen;
  bit arbitration_won;
  bit ack;
  bit passive_seen;
  bit passive_ack;
  byte unsigned passive_data[$];
  bit irq_seen;
  bit hci_complete;
  bit [31:0] descriptor;
  bit [7:0] data_length;
  bit [7:0] ibi_id;
  bit [7:0] chunks;
  bit last_status;
  bit timestamp;
  bit [2:0] status_type;
  bit error;
  bit ibi_status;
  byte unsigned hci_data[$];

  `uvm_object_utils_begin(i3c_ibi_controller_actual_item)
    `uvm_field_int(transaction_id, UVM_DEFAULT)
    `uvm_field_int(source_instance, UVM_DEFAULT)
    `uvm_field_int(source_sequence, UVM_DEFAULT)
    `uvm_field_int(addr, UVM_DEFAULT)
    `uvm_field_int(target_seen, UVM_DEFAULT)
    `uvm_field_int(arbitration_won, UVM_DEFAULT)
    `uvm_field_int(ack, UVM_DEFAULT)
    `uvm_field_int(passive_seen, UVM_DEFAULT)
    `uvm_field_int(passive_ack, UVM_DEFAULT)
    `uvm_field_queue_int(passive_data, UVM_DEFAULT)
    `uvm_field_int(irq_seen, UVM_DEFAULT)
    `uvm_field_int(hci_complete, UVM_DEFAULT)
    `uvm_field_int(descriptor, UVM_DEFAULT)
    `uvm_field_int(data_length, UVM_DEFAULT)
    `uvm_field_int(ibi_id, UVM_DEFAULT)
    `uvm_field_int(chunks, UVM_DEFAULT)
    `uvm_field_int(last_status, UVM_DEFAULT)
    `uvm_field_int(timestamp, UVM_DEFAULT)
    `uvm_field_int(status_type, UVM_DEFAULT)
    `uvm_field_int(error, UVM_DEFAULT)
    `uvm_field_int(ibi_status, UVM_DEFAULT)
    `uvm_field_queue_int(hci_data, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "i3c_ibi_controller_actual_item");
    super.new(name);
  endfunction
endclass : i3c_ibi_controller_actual_item

`endif // I3C_IBI_TRANSACTION_SV
