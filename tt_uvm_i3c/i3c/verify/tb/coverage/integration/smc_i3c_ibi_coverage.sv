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
// File        : smc_i3c_ibi_coverage.sv
// Description : Functional coverage collector for I3C IBI.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-06
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_COVERAGE_SV
`define SMC_I3C_IBI_COVERAGE_SV

class smc_i3c_ibi_coverage extends uvm_subscriber #(smc_i3c_ibi_item);
  `uvm_component_utils(smc_i3c_ibi_coverage)

  smc_i3c_ibi_attempt_coverage    attempt_cov;
  smc_i3c_ibi_completion_coverage completion_cov;
  smc_i3c_ibi_queue_irq_coverage  queue_irq_cov;
  smc_i3c_ibi_recovery_coverage   recovery_cov;

  function new(string name = "smc_i3c_ibi_coverage",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    attempt_cov    = smc_i3c_ibi_attempt_coverage::type_id::create("attempt_cov");
    completion_cov = smc_i3c_ibi_completion_coverage::type_id::create("completion_cov");
    queue_irq_cov  = smc_i3c_ibi_queue_irq_coverage::type_id::create("queue_irq_cov");
    recovery_cov   = smc_i3c_ibi_recovery_coverage::type_id::create("recovery_cov");
  endfunction

  virtual function void write(smc_i3c_ibi_item t);
    if (t == null) begin
      `uvm_warning("IBI_COV_NULL", "Ignoring null IBI coverage item")
      return;
    end

    case (t.evt_kind)
      IBI_EVT_ATTEMPT: begin
        if (!t.addr_class_valid || (t.addr_class == IBI_ADDR_UNCLASSIFIED))
          `uvm_warning("IBI_COV_ADDR_CLASS",
                       $sformatf("transaction_id=%0d has no address classification",
                                 t.transaction_id))
        attempt_cov.sample_attempt(t.role,
                                   t.src_instance,
                                   t.ibi_addr,
                                   t.addr_class,
                                   t.addr_class_valid &&
                                     (t.addr_class != IBI_ADDR_UNCLASSIFIED),
                                   t.bcr,
                                   t.ibi_enabled,
                                   t.requester_count,
                                   t.arb_outcome,
                                   t.bus_state);
      end
      IBI_EVT_COMPLETION: begin
        if (!t.attempt_context_valid)
          `uvm_warning("IBI_COV_ATTEMPT_CTX",
                       $sformatf("transaction_id=%0d completion has no ATTEMPT context",
                                 t.transaction_id))
        completion_cov.sample_completion(t.ack,
                                         t.retry_count,
                                         t.terminal_status,
                                         t.mdb_present,
                                         t.mdb,
                                         t.payload_len,
                                         t.dat_match,
                                         t.payload_policy,
                                         t.reset_error_kind,
                                         t.recovery_result,
                                         t.attempt_context_valid,
                                         t.role,
                                         t.arb_outcome,
                                         t.ibi_enabled);
      end
      IBI_EVT_QUEUE_IRQ: begin
        if (t.queue_record_write && !t.response_context_valid)
          `uvm_warning("IBI_COV_RESPONSE_CTX",
                       $sformatf("transaction_id=%0d queue write has no response context",
                                 t.transaction_id))
        queue_irq_cov.sample_queue_irq(t.fifo_level,
                                       t.record_kind,
                                       t.queue_state,
                                       t.status_source,
                                       t.irq_state,
                                       t.queue_record_write,
                                       t.response_context_valid,
                                       t.ack,
                                       t.threshold_relation_valid,
                                       t.threshold_reached);
      end
      IBI_EVT_RECOVERY: begin
        recovery_cov.sample_recovery(t);
      end
      default: begin
        `uvm_warning("IBI_COV_EVT",
                     $sformatf("Unknown IBI event kind %0d", t.evt_kind))
      end
    endcase
  endfunction

endclass : smc_i3c_ibi_coverage

`endif // SMC_I3C_IBI_COVERAGE_SV
