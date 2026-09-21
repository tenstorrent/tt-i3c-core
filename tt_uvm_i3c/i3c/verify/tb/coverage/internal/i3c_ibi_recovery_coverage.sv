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
// File        : i3c_ibi_recovery_coverage.sv
// Description : Functional coverage for independently observed IBI recovery.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-06
//
// *****************************************************************************

`ifndef I3C_IBI_RECOVERY_COVERAGE_SV
`define I3C_IBI_RECOVERY_COVERAGE_SV

class i3c_ibi_recovery_coverage extends uvm_object;
  `uvm_object_utils(i3c_ibi_recovery_coverage)

  protected bit cov_role;
  protected ibi_error_kind_e cov_cause;
  protected ibi_recovery_result_e cov_result;
  protected bit cov_trigger_seen;
  protected bit cov_queue_empty;
  protected bit cov_irq_low;
  protected bit cov_bus_idle;
  protected bit cov_followup_expected;
  protected bit cov_forward_progress;

  covergroup cg_ibi_recovery;
    option.per_instance = 1;
    option.goal = 100;

    cp_role: coverpoint cov_role {
      bins target_tx = {0};
      bins controller_rx = {1};
    }
    cp_cause: coverpoint cov_cause {
      bins reset_flush = {IBI_ERR_RESET_FLUSH};
      bins overflow = {IBI_ERR_OVERFLOW};
      bins protocol = {IBI_ERR_PROTOCOL};
      // The reviewed native RTL exposes no architectural IBI-abort recovery result.
      // Target early termination is FAILURE_PARTIAL_DATA/protocol recovery;
      // Controller ibi_abort is a policy NACK and TRANSFER_ABORT_STAT is not
      // implemented. Do not turn those distinct behaviors into a fake event.
      ignore_bins unsupported_abort = {IBI_ERR_ABORT};
      ignore_bins none = {IBI_ERR_NONE};
    }
    cp_result: coverpoint cov_result {
      bins recovered = {IBI_RECOVERED};
      // Failed cleanup is a checker/DUT failure, not a passing functional
      // scenario. Keep it visible in transactions and logs without making
      // signoff depend on deliberately breaking recovery.
      ignore_bins not_recovered = {IBI_NOT_RECOVERED};
      ignore_bins not_applicable = {IBI_RECOVERY_NA};
    }
    cp_trigger_seen: coverpoint cov_trigger_seen { bins yes = {1}; }
    cp_queue_empty: coverpoint cov_queue_empty { bins yes = {1}; }
    cp_irq_low: coverpoint cov_irq_low { bins yes = {1}; }
    cp_bus_idle: coverpoint cov_bus_idle { bins yes = {1}; }
    cp_forward_progress: coverpoint cov_forward_progress
      iff (cov_followup_expected) {
        bins yes = {1};
        ignore_bins no = {0};
      }

    x_cause_result: cross cp_cause, cp_result {
      bins reset_recovered = binsof(cp_cause.reset_flush) &&
                             binsof(cp_result.recovered);
      bins overflow_recovered = binsof(cp_cause.overflow) &&
                                binsof(cp_result.recovered);
      bins protocol_recovered = binsof(cp_cause.protocol) &&
                                binsof(cp_result.recovered);
    }
    // Score only architectural recovery ownership. Controller queue-full is
    // a policy NACK/status-record path, not an overflow recovery event, and
    // the Controller has no protocol-recovery producer in this environment.
    x_role_cause: cross cp_role, cp_cause {
      bins controller_reset = binsof(cp_role.controller_rx) &&
                              binsof(cp_cause.reset_flush);
      bins target_reset = binsof(cp_role.target_tx) &&
                          binsof(cp_cause.reset_flush);
      bins target_overflow = binsof(cp_role.target_tx) &&
                             binsof(cp_cause.overflow);
      bins target_protocol = binsof(cp_role.target_tx) &&
                             binsof(cp_cause.protocol);
      ignore_bins controller_policy_owned =
        binsof(cp_role.controller_rx) &&
        (binsof(cp_cause.overflow) || binsof(cp_cause.protocol));
    }
  endgroup

  function new(string name = "i3c_ibi_recovery_coverage");
    super.new(name);
    cg_ibi_recovery = new();
  endfunction

  function void sample_recovery(i3c_ibi_item item);
    cov_role = item.role;
    cov_cause = item.reset_error_kind;
    cov_result = item.recovery_result;
    cov_trigger_seen = item.recovery_trigger_seen;
    cov_queue_empty = item.recovery_queue_empty;
    cov_irq_low = item.recovery_irq_low;
    cov_bus_idle = item.recovery_bus_idle;
    cov_followup_expected = item.recovery_followup_expected;
    cov_forward_progress = item.recovery_forward_progress;
    cg_ibi_recovery.sample();
  endfunction
endclass : i3c_ibi_recovery_coverage

`endif // I3C_IBI_RECOVERY_COVERAGE_SV
