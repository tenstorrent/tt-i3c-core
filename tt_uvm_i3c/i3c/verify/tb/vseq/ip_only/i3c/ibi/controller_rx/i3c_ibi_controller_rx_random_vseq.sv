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
// File        : i3c_ibi_controller_rx_random_vseq.sv
// Description : Policy-aware constrained-random Controller IBI sequence.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-07
//
// *****************************************************************************

`ifndef I3C_IBI_CONTROLLER_RX_RANDOM_VSEQ_SV
`define I3C_IBI_CONTROLLER_RX_RANDOM_VSEQ_SV

class i3c_ibi_controller_rx_random_vseq extends
    i3c_ibi_controller_rx_policy_vseq;
  `uvm_object_utils(i3c_ibi_controller_rx_random_vseq)

  protected i3c_ibi_random_plan random_plan;

  function new(string name = "i3c_ibi_controller_rx_random_vseq");
    super.new(name);
  endfunction

`ifdef I3C_DV_NATIVE_RTL
`ifdef I3C_DV_NATIVE_RAL
  protected virtual task prepare_policy_scenarios();
    int unsigned max_payload;

    max_payload = 16;
    void'($value$plusargs("IBI_RANDOM_MAX_PAYLOAD=%0d", max_payload));
    if (max_payload > 8'hff)
      `uvm_fatal("IBI_CTRL_RANDOM_PAYLOAD",
                 "IBI_RANDOM_MAX_PAYLOAD must be in [0:255]")

    random_plan = i3c_ibi_random_plan::type_id::create(
      "controller_plan");
    // The current Controller RTL is limited to one IBI record per reset.
    // Coverage therefore scales with regression seeds, not loop iterations.
    random_plan.build(1, max_payload, 1'b1, 1'b0);
    random_plan.print_plan("IBI_CTRL_RANDOM_PLAN");
  endtask

  protected virtual task execute_policy_scenarios(
      input i3c_controller_hci_helper #(
        TB_ADDR_WIDTH, TB_DATA_WIDTH) hci_helper,
      input bit [6:0] unmatched_dat_addr,
      output int unsigned cases_run);
    i3c_ibi_random_item item;
    byte unsigned payload[$];
    bit [6:0] dat_addr;
    bit dat_reject;
    bit dat_payload;
    bit expected_ack;
    bit [3:0] command_id;

    if ((random_plan == null) || (random_plan.items.size() != 1))
      `uvm_fatal("IBI_CTRL_RANDOM_PLAN",
                 "Controller random plan was not prepared before DUT setup")
    item = random_plan.items[0];

    payload.delete();
    for (int unsigned index = 0; index < item.payload_len; index++)
      payload.push_back(item.mdb ^ byte'(index) ^ 8'ha5);

    dat_addr = vseq_ctx.cfg.ibi_target_addr;
    dat_reject = 1'b0;
    dat_payload = 1'b1;
    expected_ack = 1'b1;
    command_id = 4'h1;
    case (item.controller_policy)
      IBI_RANDOM_DAT_ACCEPT: begin
        command_id = 4'h1;
      end
      IBI_RANDOM_DAT_REJECT: begin
        dat_reject = 1'b1;
        expected_ack = 1'b0;
        command_id = 4'h2;
      end
      IBI_RANDOM_PAYLOAD_DISABLED: begin
        dat_payload = 1'b0;
        expected_ack = 1'b0;
        command_id = 4'h3;
      end
      IBI_RANDOM_DAT_NO_MATCH: begin
        dat_addr = unmatched_dat_addr;
        expected_ack = 1'b0;
        command_id = 4'h4;
      end
      default:
        `uvm_fatal("IBI_CTRL_RANDOM_POLICY", "Unknown random DAT policy")
    endcase

    run_policy_content_case(
      {"random ", item.policy_name()}, dat_addr, dat_reject, dat_payload,
      expected_ack, 1, command_id, item.mdb_present, item.mdb, payload,
      hci_helper);
    cases_run = 1;
  endtask
`endif
`endif
endclass : i3c_ibi_controller_rx_random_vseq

`endif // I3C_IBI_CONTROLLER_RX_RANDOM_VSEQ_SV
