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
// File        : i3c_target_send_ibi_seq.sv
// Description : Target-mode sequence that initiates an IBI request.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-24
//
// *****************************************************************************

`ifndef I3C_TARGET_SEND_IBI_SEQ_SV
`define I3C_TARGET_SEND_IBI_SEQ_SV

class i3c_target_send_ibi_seq extends
    uvm_sequence #(i3c_seq_item, i3c_seq_item);
  `uvm_object_utils(i3c_target_send_ibi_seq)

  bit [6:0] target_addr;
  bit mdb_present = 1'b1;
  // The standard IBI tests deliberately keep their existing MDB-bearing
  // behavior.  A focused requirement-driven reproduction may opt in to the
  // address-only IBI form (no MDB and no additional data); it must never be
  // reached accidentally through an empty payload.
  bit allow_no_mdb_ibi = 1'b0;
  bit [7:0] mdb;
  byte unsigned payload[$];
  bit start_on_idle = 1'b1;
  bit response_valid;
  bit observed_ack;

  function new(string name = "i3c_target_send_ibi_seq");
    super.new(name);
  endfunction

  virtual task body();
    i3c_seq_item response;
    i3c_seq_item transfer_req;
    i3c_seq_item transfer_response;
    int unsigned byte_count;

    byte_count = (mdb_present ? 1 : 0) + payload.size();
    if ((byte_count == 0) && !allow_no_mdb_ibi)
      `uvm_fatal("IBI_TARGET_EMPTY",
                 "Zero-byte IBI requires explicit allow_no_mdb_ibi opt-in")
    req = i3c_seq_item::type_id::create("req");
    start_item(req);
    req.i3c = 1'b1;
    req.addr = target_addr;
    req.dir = 1'b1;
    req.dev_ack = 1'b0;
    req.end_with_rstart = 1'b0;
    req.is_daa = 1'b0;
    req.data.delete();
    if (mdb_present)
      req.data.push_back(mdb);
    foreach (payload[index])
      req.data.push_back(payload[index]);
    req.data_cnt = byte_count;
    req.T_bit.delete();
    for (int unsigned index = 0; index < byte_count; index++)
      req.T_bit.push_back(index != (byte_count - 1));
    req.IBI = 1'b1;
    req.IBI_ADDR = target_addr;
    req.IBI_START = start_on_idle;
    req.IBI_ACK = 1'b0;
    finish_item(req);
    get_response(response);

    response_valid = response != null;
    if (!response_valid)
      `uvm_fatal("IBI_TARGET_NO_RESPONSE",
                 "Device-mode driver returned no response for target IBI")
    observed_ack = response.dev_ack;

    // The vendored I3C Device driver returns after address arbitration.
    // A second item advances DrvSelectNext and transmits the MDB/payload.
    if (observed_ack) begin
      transfer_req = i3c_seq_item::type_id::create("transfer_req");
      transfer_req.copy(req);
      transfer_req.IBI_START = 1'b0;
      start_item(transfer_req);
      finish_item(transfer_req);
      get_response(transfer_response);
      if (transfer_response == null)
        `uvm_fatal("IBI_TARGET_NO_TRANSFER_RESPONSE",
                   "Device-mode driver returned no payload response")
    end
  endtask
endclass : i3c_target_send_ibi_seq

`endif // I3C_TARGET_SEND_IBI_SEQ_SV
