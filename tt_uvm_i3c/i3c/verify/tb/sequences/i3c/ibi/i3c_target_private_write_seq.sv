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
// File        : i3c_target_private_write_seq.sv
// Description : UVM sequence for I3C target private write.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-28
//
// *****************************************************************************

`ifndef I3C_TARGET_PRIVATE_WRITE_SEQ_SV
`define I3C_TARGET_PRIVATE_WRITE_SEQ_SV

// One deterministic Device-mode response to a Controller private write. The
// bundled/reviewed I3C VIP returns after address sampling, then consumes a second item to
// drive ACK and receive the data/T-bit through STOP.
class i3c_target_private_write_seq extends
    uvm_sequence #(i3c_seq_item, i3c_seq_item);
  `uvm_object_utils(i3c_target_private_write_seq)

  bit [6:0] target_addr;
  int unsigned expected_byte_count = 1;
  bit pause_before_data;
  uvm_event address_seen_event;
  uvm_event continue_event;

  bit address_response_valid;
  bit transfer_response_valid;
  bit address_matched;
  bit transfer_done;
  bit [6:0] observed_addr;
  bit observed_dir;
  byte unsigned observed_data[$];
  bit observed_t_bits[$];

  function new(string name = "i3c_target_private_write_seq");
    super.new(name);
    address_seen_event = new({name, "_address_seen"});
    continue_event = new({name, "_continue"});
  endfunction

  virtual task body();
    i3c_seq_item address_response;
    i3c_seq_item transfer_req;
    i3c_seq_item transfer_response;

    req = i3c_seq_item::type_id::create("address_req");
    start_item(req);
    req.i3c = 1'b1;
    req.addr = target_addr;
    req.dir = 1'b0;
    req.dev_ack = 1'b1;
    req.end_with_rstart = 1'b0;
    req.is_daa = 1'b0;
    req.data.delete();
    req.data_cnt = 0;
    req.T_bit.delete();
    req.IBI = 1'b0;
    req.IBI_ADDR = '0;
    req.IBI_START = 1'b0;
    req.IBI_ACK = 1'b0;
    finish_item(req);
    get_response(address_response);

    address_response_valid = address_response != null;
    if (!address_response_valid) begin
      `uvm_error("I3C_TARGET_WRITE_ADDRESS",
                 "Device-mode driver returned no private-write address response")
      return;
    end
    observed_addr = address_response.addr;
    observed_dir = address_response.dir;
    address_matched = (observed_addr == target_addr) && !observed_dir;
    address_seen_event.trigger();
    if (pause_before_data)
      continue_event.wait_on();

    transfer_req = i3c_seq_item::type_id::create("transfer_req");
    transfer_req.i3c = 1'b1;
    transfer_req.addr = observed_addr;
    transfer_req.dir = observed_dir;
    transfer_req.dev_ack = address_matched;
    transfer_req.end_with_rstart = 1'b0;
    transfer_req.is_daa = 1'b0;
    transfer_req.data.delete();
    transfer_req.data_cnt = expected_byte_count;
    transfer_req.T_bit.delete();
    repeat (expected_byte_count)
      transfer_req.T_bit.push_back(1'b1);
    transfer_req.IBI = 1'b0;
    transfer_req.IBI_ADDR = '0;
    transfer_req.IBI_START = 1'b0;
    transfer_req.IBI_ACK = 1'b0;
    start_item(transfer_req);
    finish_item(transfer_req);
    get_response(transfer_response);

    transfer_response_valid = transfer_response != null;
    if (!transfer_response_valid) begin
      `uvm_error("I3C_TARGET_WRITE_DATA",
                 "Device-mode driver returned no private-write data response")
      return;
    end
    foreach (transfer_response.data[index])
      observed_data.push_back(transfer_response.data[index]);
    foreach (transfer_response.T_bit[index])
      observed_t_bits.push_back(transfer_response.T_bit[index]);
    transfer_done = address_matched &&
                    !transfer_response.end_with_rstart &&
                    (observed_data.size() == expected_byte_count) &&
                    (observed_t_bits.size() == expected_byte_count);
  endtask
endclass : i3c_target_private_write_seq

`endif // I3C_TARGET_PRIVATE_WRITE_SEQ_SV
