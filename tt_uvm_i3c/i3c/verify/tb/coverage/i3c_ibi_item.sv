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
// File        : i3c_ibi_item.sv
// Description : UVM transaction item for I3C IBI.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-06
//
// *****************************************************************************

`ifndef I3C_IBI_ITEM_SV
`define I3C_IBI_ITEM_SV

// Event kind selecting which covergroup snapshot this item feeds.
typedef enum bit [2:0] {
  IBI_EVT_ATTEMPT    = 3'd0,
  IBI_EVT_COMPLETION = 3'd1,
  IBI_EVT_QUEUE_IRQ  = 3'd2,
  IBI_EVT_RECOVERY   = 3'd3
} ibi_evt_e;

// Address classification is produced by the monitor from the core's address
// policy (i3c_pkg::is_i3c_rsvd_addr), not from ranges duplicated in coverage.
typedef enum bit [1:0] {
  IBI_ADDR_VALID        = 2'd0,
  IBI_ADDR_RESERVED     = 2'd1,
  IBI_ADDR_BROADCAST    = 2'd2,
  IBI_ADDR_UNCLASSIFIED = 2'd3
} ibi_addr_class_e;

// Matches i3c_pkg::ibi_status_e without introducing an RTL-package dependency
// into the coverage package compile order.
typedef enum bit [2:0] {
  IBI_STATUS_SUCCESS             = 3'b000,
  IBI_STATUS_FAILURE_NACK        = 3'b001,
  IBI_STATUS_FAILURE_PARTIAL_DATA = 3'b010,
  IBI_STATUS_FAILURE_RETRY       = 3'b011,
  IBI_STATUS_FAILURE_ADDRESS_ARB = 3'b100
} ibi_terminal_status_e;

// Error cause and recovery outcome are independent dimensions. In particular,
// recovery is an outcome, not another error encoding.
typedef enum bit [2:0] {
  IBI_ERR_NONE           = 3'd0,
  IBI_ERR_RESET_FLUSH    = 3'd1,
  IBI_ERR_OVERFLOW       = 3'd2,
  IBI_ERR_ABORT          = 3'd3,
  IBI_ERR_PROTOCOL       = 3'd4
} ibi_error_kind_e;

typedef enum bit [1:0] {
  // Contract: NA is used only with IBI_ERR_NONE. Every non-NONE cause must
  // report either RECOVERED or NOT_RECOVERED.
  IBI_RECOVERY_NA        = 2'd0,
  IBI_RECOVERED          = 2'd1,
  IBI_NOT_RECOVERED      = 2'd2
} ibi_recovery_result_e;

class i3c_ibi_item extends uvm_sequence_item;

  // ---- routing ----
  ibi_evt_e   evt_kind;
  longint unsigned transaction_id;

  // ---- ATTEMPT context (request + arbitration + capability + entry) ----
  bit         role;            // 0 = DUT target (issues IBI), 1 = DUT controller (receives)
  bit [2:0]   src_instance;    // source index, bounded by central TB configuration
  bit [6:0]   ibi_addr;        // dynamic address that issued the IBI
  ibi_addr_class_e addr_class; // decoded by monitor from the core address policy
  bit         addr_class_valid;
  bit [7:0]   bcr;             // target BCR: bit2 = MDB, bit1 = IBI request capable
  bit         ibi_enabled;     // IBI enable state (DAT / control)
  int unsigned requester_count;// number of targets arbitrating this IBI
  bit [1:0]   arb_outcome;     // 0 = sole, 1 = won, 2 = lost
  bit [1:0]   bus_state;       // 0 = bus_available, 1 = bus_start, 2 = after_transfer, 3 = busy

  // ---- COMPLETION content + response + policy + reset/error ----
  bit         attempt_context_valid; // role/arb/enable belong to this transaction_id
  bit         ack;             // 1 = ACK, 0 = NACK
  int unsigned retry_count;    // arbitration retries before terminal result
  ibi_terminal_status_e terminal_status;
  bit         mdb_present;     // MDB byte present
  bit [7:0]   mdb;             // Mandatory Data Byte (bit[7:5] = group)
  int unsigned payload_len;    // payload bytes after MDB
  bit         dat_match;       // controller: address matched a DAT entry
  bit [1:0]   payload_policy;  // matched DAT policy; 0 none/no match, 1 mandatory, 2 optional
  ibi_error_kind_e reset_error_kind;
  ibi_recovery_result_e recovery_result;
  bit         expected_content_valid;
  bit         expected_mdb_present;
  bit [7:0]   expected_mdb;
  int unsigned expected_payload_len;

  // ---- QUEUE / IRQ backend ----
  bit         queue_record_write;     // 1 only for a direct enqueue snapshot
  bit         response_context_valid; // ack belongs to this transaction_id
  int unsigned fifo_level;     // architectural IBI_QUEUE_DEPTH snapshot
  bit [1:0]   record_kind;     // 0 = status_only, 1 = with_data; 2/3 reserved
  bit [1:0]   queue_state;     // architectural states: 0 normal, 1 empty, 2 full
  bit [2:0]   status_source;   // 0 thld,1 full,2 done,3 error,4 pending
  bit [1:0]   irq_state;       // 0 = idle, 1 = asserted, 2 = w1c_cleared, 3 = forced
  bit         irq_enabled;     // Controller interrupt-signal enable snapshot
  bit         threshold_relation_valid;
  bit         threshold_reached; // free entries are at or above IBI_THLD

  // ---- RECOVERY result (published only by the passive recovery checker) ----
  bit         recovery_trigger_seen;
  bit         recovery_queue_empty;
  bit         recovery_irq_low;
  bit         recovery_bus_idle;
  bit         recovery_followup_expected;
  bit         recovery_forward_progress;

  `uvm_object_utils_begin(i3c_ibi_item)
    `uvm_field_enum(ibi_evt_e, evt_kind, UVM_DEFAULT)
    `uvm_field_int(transaction_id,   UVM_DEFAULT)
    `uvm_field_int(role,             UVM_DEFAULT)
    `uvm_field_int(src_instance,     UVM_DEFAULT)
    `uvm_field_int(ibi_addr,         UVM_DEFAULT)
    `uvm_field_enum(ibi_addr_class_e, addr_class, UVM_DEFAULT)
    `uvm_field_int(addr_class_valid, UVM_DEFAULT)
    `uvm_field_int(bcr,              UVM_DEFAULT)
    `uvm_field_int(ibi_enabled,      UVM_DEFAULT)
    `uvm_field_int(requester_count,  UVM_DEFAULT)
    `uvm_field_int(arb_outcome,      UVM_DEFAULT)
    `uvm_field_int(bus_state,        UVM_DEFAULT)
    `uvm_field_int(attempt_context_valid, UVM_DEFAULT)
    `uvm_field_int(ack,              UVM_DEFAULT)
    `uvm_field_int(retry_count,      UVM_DEFAULT)
    `uvm_field_enum(ibi_terminal_status_e, terminal_status, UVM_DEFAULT)
    `uvm_field_int(mdb_present,      UVM_DEFAULT)
    `uvm_field_int(mdb,              UVM_DEFAULT)
    `uvm_field_int(payload_len,      UVM_DEFAULT)
    `uvm_field_int(dat_match,        UVM_DEFAULT)
    `uvm_field_int(payload_policy,   UVM_DEFAULT)
    `uvm_field_enum(ibi_error_kind_e, reset_error_kind, UVM_DEFAULT)
    `uvm_field_enum(ibi_recovery_result_e, recovery_result, UVM_DEFAULT)
    `uvm_field_int(expected_content_valid, UVM_DEFAULT)
    `uvm_field_int(expected_mdb_present, UVM_DEFAULT)
    `uvm_field_int(expected_mdb, UVM_DEFAULT)
    `uvm_field_int(expected_payload_len, UVM_DEFAULT)
    `uvm_field_int(queue_record_write, UVM_DEFAULT)
    `uvm_field_int(response_context_valid, UVM_DEFAULT)
    `uvm_field_int(fifo_level,       UVM_DEFAULT)
    `uvm_field_int(record_kind,      UVM_DEFAULT)
    `uvm_field_int(queue_state,      UVM_DEFAULT)
    `uvm_field_int(status_source,    UVM_DEFAULT)
    `uvm_field_int(irq_state,        UVM_DEFAULT)
    `uvm_field_int(irq_enabled,      UVM_DEFAULT)
    `uvm_field_int(threshold_relation_valid, UVM_DEFAULT)
    `uvm_field_int(threshold_reached, UVM_DEFAULT)
    `uvm_field_int(recovery_trigger_seen, UVM_DEFAULT)
    `uvm_field_int(recovery_queue_empty, UVM_DEFAULT)
    `uvm_field_int(recovery_irq_low, UVM_DEFAULT)
    `uvm_field_int(recovery_bus_idle, UVM_DEFAULT)
    `uvm_field_int(recovery_followup_expected, UVM_DEFAULT)
    `uvm_field_int(recovery_forward_progress, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "i3c_ibi_item");
    super.new(name);
    addr_class = IBI_ADDR_UNCLASSIFIED;
  endfunction

endclass : i3c_ibi_item

`endif // I3C_IBI_ITEM_SV
