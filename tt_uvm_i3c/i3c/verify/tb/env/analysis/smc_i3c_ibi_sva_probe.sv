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
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-06
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

  virtual function void write(smc_i3c_ibi_item t);
    if (t == null)
      return;

    case (t.evt_kind)
      IBI_EVT_ATTEMPT: begin
        vif.i3c_sva_attempt_role = t.role;
        vif.i3c_sva_attempt_addr_class = t.addr_class;
        vif.i3c_sva_attempt_bcr = t.bcr;
        vif.i3c_sva_attempt_ibi_enabled = t.ibi_enabled;
        vif.i3c_sva_attempt_requester_count = t.requester_count;
        vif.i3c_sva_attempt_arb_outcome = t.arb_outcome;
        vif.i3c_sva_attempt_bus_state = t.bus_state;
        vif.i3c_sva_attempt_seq++;
      end
      IBI_EVT_COMPLETION: begin
        vif.i3c_sva_completion_transaction_id = t.transaction_id;
        vif.i3c_sva_completion_role = t.role;
        vif.i3c_sva_completion_ack = t.ack;
        vif.i3c_sva_completion_retry_count = t.retry_count;
        vif.i3c_sva_completion_terminal_status = t.terminal_status;
        vif.i3c_sva_completion_mdb_present = t.mdb_present;
        vif.i3c_sva_completion_mdb = t.mdb;
        vif.i3c_sva_completion_payload_len = t.payload_len;
        vif.i3c_sva_completion_dat_match = t.dat_match;
        vif.i3c_sva_completion_payload_policy = t.payload_policy;
        vif.i3c_sva_completion_ibi_enabled = t.ibi_enabled;
        vif.i3c_sva_completion_error_kind = t.reset_error_kind;
        vif.i3c_sva_completion_recovery_result = t.recovery_result;
        vif.i3c_sva_expected_content_valid = t.expected_content_valid;
        vif.i3c_sva_expected_mdb_present = t.expected_mdb_present;
        vif.i3c_sva_expected_mdb = t.expected_mdb;
        vif.i3c_sva_expected_payload_len = t.expected_payload_len;
        vif.i3c_sva_completion_seq++;
      end
      IBI_EVT_QUEUE_IRQ: begin
        vif.i3c_sva_queue_transaction_id = t.transaction_id;
        vif.i3c_sva_queue_record_write = t.queue_record_write;
        vif.i3c_sva_queue_response_context_valid =
          t.response_context_valid;
        vif.i3c_sva_queue_response_ack = t.ack;
        vif.i3c_sva_queue_state = t.queue_state;
        vif.i3c_sva_queue_status_source = t.status_source;
        vif.i3c_sva_queue_irq_state = t.irq_state;
        vif.i3c_sva_queue_role = t.role;
        vif.i3c_sva_queue_irq_enabled = t.irq_enabled;
        vif.i3c_sva_queue_seq++;
      end
      IBI_EVT_RECOVERY: begin
        vif.i3c_sva_recovery_role = t.role;
        vif.i3c_sva_recovery_cause = t.reset_error_kind;
        vif.i3c_sva_recovery_result = t.recovery_result;
        vif.i3c_sva_recovery_trigger_seen = t.recovery_trigger_seen;
        vif.i3c_sva_recovery_queue_empty = t.recovery_queue_empty;
        vif.i3c_sva_recovery_irq_low = t.recovery_irq_low;
        vif.i3c_sva_recovery_bus_idle = t.recovery_bus_idle;
        vif.i3c_sva_recovery_followup_expected =
          t.recovery_followup_expected;
        vif.i3c_sva_recovery_forward_progress =
          t.recovery_forward_progress;
        vif.i3c_sva_recovery_seq++;
      end
      default: begin
      end
    endcase
  endfunction
endclass : smc_i3c_ibi_sva_probe

`endif // SMC_I3C_IBI_SVA_PROBE_SV
