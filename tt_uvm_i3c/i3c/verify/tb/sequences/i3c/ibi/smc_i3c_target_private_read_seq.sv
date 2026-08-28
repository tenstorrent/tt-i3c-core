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
// File        : smc_i3c_target_private_read_seq.sv
// Description : UVM Target response to a Controller private read.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-05
//
// *****************************************************************************

`ifndef SMC_I3C_TARGET_PRIVATE_READ_SEQ_SV
`define SMC_I3C_TARGET_PRIVATE_READ_SEQ_SV

// The Device-mode VIP returns once after sampling the address and direction.
// A second item ACKs the matching read and sends the configured data/T bits.
class smc_i3c_target_private_read_seq extends
    uvm_sequence #(i3c_seq_item, i3c_seq_item);
  `uvm_object_utils(smc_i3c_target_private_read_seq)

  bit [6:0] target_addr;
  byte unsigned response_data[$];

  bit address_response_valid;
  bit transfer_response_valid;
  bit address_matched;
  bit transfer_done;
  bit [6:0] observed_addr;
  bit observed_dir;
  uvm_event address_seen_event;

  function new(string name = "smc_i3c_target_private_read_seq");
    super.new(name);
    address_seen_event = new({name, "_address_seen"});
  endfunction

  virtual task body();
    i3c_seq_item address_response;
    i3c_seq_item transfer_req;
    i3c_seq_item transfer_response;

    if (response_data.size() == 0)
      `uvm_fatal("I3C_TARGET_READ_EMPTY",
                 "Private-read target response must contain at least one byte")

    req = i3c_seq_item::type_id::create("address_req");
    start_item(req);
    req.i3c = 1'b1;
    req.addr = target_addr;
    req.dir = 1'b1;
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
      `uvm_error("I3C_TARGET_READ_ADDRESS",
                 "Device-mode driver returned no private-read address response")
      return;
    end
    observed_addr = address_response.addr;
    observed_dir = address_response.dir;
    address_matched =
      (observed_addr == target_addr) && observed_dir;
    address_seen_event.trigger();

    transfer_req = i3c_seq_item::type_id::create("transfer_req");
    transfer_req.i3c = 1'b1;
    transfer_req.addr = observed_addr;
    transfer_req.dir = observed_dir;
    transfer_req.dev_ack = address_matched;
    transfer_req.end_with_rstart = 1'b0;
    transfer_req.is_daa = 1'b0;
    transfer_req.data.delete();
    foreach (response_data[index])
      transfer_req.data.push_back(response_data[index]);
    transfer_req.data_cnt = response_data.size();
    transfer_req.T_bit.delete();
    foreach (response_data[index])
      transfer_req.T_bit.push_back(index != (response_data.size() - 1));
    transfer_req.IBI = 1'b0;
    transfer_req.IBI_ADDR = '0;
    transfer_req.IBI_START = 1'b0;
    transfer_req.IBI_ACK = 1'b0;
    start_item(transfer_req);
    finish_item(transfer_req);
    get_response(transfer_response);

    transfer_response_valid = transfer_response != null;
    if (!transfer_response_valid) begin
      `uvm_error("I3C_TARGET_READ_DATA",
                 "Device-mode driver returned no private-read data response")
      return;
    end
    transfer_done = address_matched &&
                    !transfer_response.end_with_rstart;
  endtask
endclass : smc_i3c_target_private_read_seq

`endif // SMC_I3C_TARGET_PRIVATE_READ_SEQ_SV
