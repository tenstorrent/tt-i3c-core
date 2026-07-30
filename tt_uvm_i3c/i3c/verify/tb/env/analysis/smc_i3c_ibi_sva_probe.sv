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
// File        : smc_i3c_ibi_sva_probe.sv
// Description : Bridges normalized UVM IBI events to top-level SVA probes.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-29
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_SVA_PROBE_SV
`define SMC_I3C_IBI_SVA_PROBE_SV

class smc_i3c_ibi_sva_probe extends uvm_subscriber #(smc_i3c_ibi_item);
  `uvm_component_utils(smc_i3c_ibi_sva_probe)

  virtual smc_peripherals_if vif;

  function new(string name = "smc_i3c_ibi_sva_probe",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (vif == null)
      `uvm_fatal("IBI_SVA_PROBE_VIF",
                 "Normalized IBI SVA probe requires smc_peripherals_if")
  endfunction

  virtual function void write(smc_i3c_ibi_item item);
    if (item == null)
      return;

    case (item.evt_kind)
      IBI_EVT_ATTEMPT: begin
        vif.i3c_sva_attempt_role = item.role;
        vif.i3c_sva_attempt_addr_class = item.addr_class;
        vif.i3c_sva_attempt_bcr = item.bcr;
        vif.i3c_sva_attempt_ibi_enabled = item.ibi_enabled;
        vif.i3c_sva_attempt_requester_count = item.requester_count;
        vif.i3c_sva_attempt_arb_outcome = item.arb_outcome;
        vif.i3c_sva_attempt_bus_state = item.bus_state;
        vif.i3c_sva_attempt_seq++;
      end
      IBI_EVT_COMPLETION: begin
        vif.i3c_sva_completion_transaction_id = item.transaction_id;
        vif.i3c_sva_completion_role = item.role;
        vif.i3c_sva_completion_ack = item.ack;
        vif.i3c_sva_completion_retry_count = item.retry_count;
        vif.i3c_sva_completion_terminal_status = item.terminal_status;
        vif.i3c_sva_completion_mdb_present = item.mdb_present;
        vif.i3c_sva_completion_mdb = item.mdb;
        vif.i3c_sva_completion_payload_len = item.payload_len;
        vif.i3c_sva_completion_dat_match = item.dat_match;
        vif.i3c_sva_completion_payload_policy = item.payload_policy;
        vif.i3c_sva_completion_ibi_enabled = item.ibi_enabled;
        vif.i3c_sva_completion_error_kind = item.reset_error_kind;
        vif.i3c_sva_completion_recovery_result = item.recovery_result;
        vif.i3c_sva_expected_content_valid = item.expected_content_valid;
        vif.i3c_sva_expected_mdb_present = item.expected_mdb_present;
        vif.i3c_sva_expected_mdb = item.expected_mdb;
        vif.i3c_sva_expected_payload_len = item.expected_payload_len;
        vif.i3c_sva_completion_seq++;
      end
      IBI_EVT_QUEUE_IRQ: begin
        vif.i3c_sva_queue_transaction_id = item.transaction_id;
        vif.i3c_sva_queue_record_write = item.queue_record_write;
        vif.i3c_sva_queue_response_context_valid =
          item.response_context_valid;
        vif.i3c_sva_queue_response_ack = item.ack;
        vif.i3c_sva_queue_record_kind = item.record_kind;
        vif.i3c_sva_queue_state = item.queue_state;
        vif.i3c_sva_queue_status_source = item.status_source;
        vif.i3c_sva_queue_irq_state = item.irq_state;
        vif.i3c_sva_queue_seq++;
      end
      default: begin
      end
    endcase
  endfunction
endclass : smc_i3c_ibi_sva_probe

`endif // SMC_I3C_IBI_SVA_PROBE_SV
