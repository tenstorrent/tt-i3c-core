// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 VNCHIP LABS
// Authors: Huynh Pham Anh Duy, Thai Hai Dang
`ifndef SMC_I3C_IBI_BLOCKED_COVERAGE_SV
`define SMC_I3C_IBI_BLOCKED_COVERAGE_SV

class smc_i3c_ibi_blocked_coverage extends uvm_object;
  `uvm_object_utils(smc_i3c_ibi_blocked_coverage)

  protected bit cov_role;
  protected bit cov_request_busy;
  protected bit cov_start_blocked;
  protected bit cov_transfer_preserved;
  protected bit cov_deferred;
  protected bit cov_retry_after_idle;

  covergroup cg_ibi_blocked;
    option.per_instance = 1;
    option.goal = 100;
    cp_role: coverpoint cov_role {
      bins target_tx = {0};
      bins controller_rx = {1};
    }
    cp_request_busy: coverpoint cov_request_busy { bins observed = {1}; }
    cp_start_blocked: coverpoint cov_start_blocked { bins blocked = {1}; }
    cp_transfer_preserved: coverpoint cov_transfer_preserved { bins preserved = {1}; }
    cp_deferred: coverpoint cov_deferred { bins deferred = {1}; }
    cp_retry_after_idle: coverpoint cov_retry_after_idle { bins retried = {1}; }
    x_block_lifecycle: cross cp_role, cp_request_busy, cp_start_blocked,
                             cp_transfer_preserved, cp_deferred,
                             cp_retry_after_idle;
  endgroup

  function new(string name = "smc_i3c_ibi_blocked_coverage");
    super.new(name);
    cg_ibi_blocked = new();
  endfunction

  function void sample_blocked(bit role, bit request_busy, bit start_blocked,
                               bit transfer_preserved, bit deferred,
                               bit retry_after_idle);
    cov_role = role;
    cov_request_busy = request_busy;
    cov_start_blocked = start_blocked;
    cov_transfer_preserved = transfer_preserved;
    cov_deferred = deferred;
    cov_retry_after_idle = retry_after_idle;
    cg_ibi_blocked.sample();
  endfunction
endclass

`endif
