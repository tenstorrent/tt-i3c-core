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
// File        : smc_i3c_ibi_queue_irq_coverage.sv
// Description : Functional coverage collector for I3C IBI queue IRQ.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-24
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_QUEUE_IRQ_COVERAGE_SV
`define SMC_I3C_IBI_QUEUE_IRQ_COVERAGE_SV

class smc_i3c_ibi_queue_irq_coverage extends uvm_object;
  `uvm_object_utils(smc_i3c_ibi_queue_irq_coverage)

  localparam bit [1:0] REC_STATUS = 2'd0, REC_DATA = 2'd1, REC_ERROR = 2'd2;
  localparam bit [1:0] QS_NORMAL = 2'd0, QS_EMPTY = 2'd1,
                       QS_FULL   = 2'd2, QS_OVERFLOW = 2'd3;
  localparam bit [2:0] SRC_THLD = 3'd0, SRC_FULL = 3'd1, SRC_DONE = 3'd2,
                       SRC_ERROR = 3'd3, SRC_PENDING = 3'd4;
  localparam bit [1:0] IRQ_IDLE = 2'd0, IRQ_ASSERT = 2'd1,
                       IRQ_W1C  = 2'd2, IRQ_FORCED = 2'd3;

  protected int unsigned cov_fifo_level;
  protected bit [1:0]   cov_record_kind;
  protected bit [1:0]   cov_queue_state;
  protected bit [2:0]   cov_status_source;
  protected bit [1:0]   cov_irq_state;
  protected bit         cov_queue_record_write;
  protected bit         cov_response_ctx_valid;
  protected bit         cov_ack_ctx; // mirror (weight 0)
  protected bit         cov_threshold_relation_valid;
  protected bit         cov_threshold_reached;

  covergroup cg_ibi_queue_irq;
    option.per_instance = 1;
    option.goal         = 100;

    // Absolute occupancy buckets (programmable depth -> no hardcoded max).
    cp_fifo_level: coverpoint cov_fifo_level {
      bins empty = {0};
      bins low   = {[1:3]};
      bins mid   = {[4:7]};
      bins high  = {[8:$]};
    }

    cp_record_kind: coverpoint cov_record_kind {
      bins status_only = {REC_STATUS};
      bins with_data   = {REC_DATA};
      bins error_rec   = {REC_ERROR};
    }

    cp_queue_state: coverpoint cov_queue_state {
      bins normal   = {QS_NORMAL};
      bins empty    = {QS_EMPTY};
      bins full     = {QS_FULL};
      bins overflow = {QS_OVERFLOW};
    }

    cp_status_source: coverpoint cov_status_source {
      bins thld    = {SRC_THLD};
      bins full    = {SRC_FULL};
      bins done    = {SRC_DONE};
      bins error   = {SRC_ERROR};
      bins pending = {SRC_PENDING};
    }

    cp_irq_state: coverpoint cov_irq_state {
      bins idle        = {IRQ_IDLE};
      bins asserted    = {IRQ_ASSERT};
      bins w1c_cleared = {IRQ_W1C};
      bins forced      = {IRQ_FORCED};
    }

    cp_threshold_relation: coverpoint cov_threshold_reached
        iff (cov_threshold_relation_valid) {
      bins below   = {0};
      bins reached = {1};
    }

    // ---- mirror coverpoint (weight 0: cross only) ----
    cp_response_h: coverpoint cov_ack_ctx iff (cov_response_ctx_valid) {
      option.weight = 0;
      bins nack = {0};
      bins ack  = {1};
    }

    // FIFO occupancy comes from architectural CSR snapshots. Response context
    // is the most recently completed IBI and is valid only after scoreboard
    // correlation.
    x_queue: cross cp_fifo_level, cp_response_h {
      ignore_bins empty_on_record_write = binsof(cp_fifo_level.empty);
    }

    x_interrupt: cross cp_status_source, cp_irq_state;
  endgroup

  function new(string name = "smc_i3c_ibi_queue_irq_coverage");
    super.new(name);
    cg_ibi_queue_irq = new();
  endfunction

  virtual function void sample_queue_irq(input int unsigned fifo_level,
                                         input bit [1:0]    record_kind,
                                         input bit [1:0]    queue_state,
                                         input bit [2:0]    status_source,
                                         input bit [1:0]    irq_state,
                                         input bit          queue_record_write,
                                         input bit          response_ctx_valid,
                                         input bit          ack_ctx,
                                         input bit          threshold_relation_valid,
                                         input bit          threshold_reached);
    cov_fifo_level    = fifo_level;
    cov_record_kind   = record_kind;
    cov_queue_state   = queue_state;
    cov_status_source = status_source;
    cov_irq_state     = irq_state;
    cov_queue_record_write = queue_record_write;
    cov_response_ctx_valid = response_ctx_valid;
    cov_ack_ctx       = ack_ctx;
    cov_threshold_relation_valid = threshold_relation_valid;
    cov_threshold_reached = threshold_reached;
    cg_ibi_queue_irq.sample();
  endfunction

endclass : smc_i3c_ibi_queue_irq_coverage

`endif // SMC_I3C_IBI_QUEUE_IRQ_COVERAGE_SV
