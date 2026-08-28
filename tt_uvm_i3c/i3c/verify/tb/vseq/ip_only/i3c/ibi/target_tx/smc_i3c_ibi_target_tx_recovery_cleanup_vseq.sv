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
// File        : smc_i3c_ibi_target_tx_recovery_cleanup_vseq.sv
// Description : Target-role IBI reset cleanup and forward-progress sequence.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-06
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_TARGET_TX_RECOVERY_CLEANUP_VSEQ_SV
`define SMC_I3C_IBI_TARGET_TX_RECOVERY_CLEANUP_VSEQ_SV

class smc_i3c_ibi_target_tx_recovery_cleanup_vseq extends smc_i3c_ibi_target_tx_ack_nack_vseq;
  `uvm_object_utils(smc_i3c_ibi_target_tx_recovery_cleanup_vseq)

  function new(string name = "smc_i3c_ibi_target_tx_recovery_cleanup_vseq");
    super.new(name);
  endfunction

  virtual task body();
    if ((vseq_ctx == null) || (vseq_ctx.services == null))
      `uvm_fatal("IBI_RECOVERY_CONTEXT", "Invalid recovery vseq context")
    vseq_ctx.services.wait_reset_release();

    if (!vseq_ctx.cfg.has_rtl)
      `uvm_fatal("IBI_RECOVERY_MODE",
                 "Target recovery cleanup requires DUT_MODE=rtl")
    if (vseq_ctx.cfg.ibi_dut_role != SMC_I3C_IBI_DUT_TARGET)
      `uvm_fatal("IBI_RECOVERY_ROLE",
                 "Target recovery cleanup requires DUT-target role")

`ifdef SMC_USE_I3C_RTL
`ifdef SMC_USE_I3C_RAL
    begin
      smc_i3c_ral_model ral;
      smc_i3c_ibi_recovery_checker recovery_checker;
      bit completed;
      bit recovered;
      int unsigned recovery_samples_before;

      if (vseq_ctx.i3c_sqr == null)
        `uvm_fatal("IBI_RECOVERY_SQR", "I3C host sequencer is unavailable")
      if (!vseq_ctx.cfg.has_ibi_scoreboard)
        `uvm_fatal("IBI_RECOVERY_SB",
                   "Target recovery cleanup requires the IBI scoreboard")
      recovery_checker = vseq_ctx.i3c_ibi_recovery_checker;
      if (recovery_checker == null)
        `uvm_fatal("IBI_RECOVERY_CHECKER",
                   "Target recovery checker is unavailable")

      ral = get_i3c_ral_model();
      initialize_target_ibi(ral);
      write_field(ral.I3C_EC.TTI.INTERRUPT_ENABLE.IBI_DONE_EN, 1,
                  "enable IBI_DONE for recovery cleanup");
      clear_w1c_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 1,
                      "clear stale IBI_DONE before recovery cleanup");
      wait_irq(1'b0, "verify recovery cleanup starts with IRQ low");

      recovery_samples_before = vseq_ctx.cfg.ibi_cov_recovery_samples;
      recovery_checker.arm_recovery(IBI_ERR_RESET_FLUSH, 1'b0, 1'b1);
      run_mdb_only_ibi_response(ral, 1'b0,
                                IBI_STATUS_FAILURE_NACK,
                                "recovery-trigger NACK");
      run_mdb_only_ibi_response(ral, 1'b1,
                                IBI_STATUS_SUCCESS,
                                "post-recovery ACK", 1'b1);
      recovery_checker.wait_for_result(
        vseq_ctx.cfg.ibi_timeout_cycles, completed, recovered);
      if (!completed || !recovered)
        `uvm_fatal("IBI_RECOVERY_RESULT",
                   "Target IBI reset cleanup did not restore forward progress")
      if ((vseq_ctx.cfg.ibi_cov_recovery_samples -
           recovery_samples_before) != 1)
        `uvm_fatal("IBI_RECOVERY_COVERAGE",
                   "Target recovery produced an invalid number of recovery samples")

      `uvm_info("IBI_RECOVERY_PASS",
                $sformatf("Target IBI reset cleanup passed: DA=0x%02h MDB=0x%02h",
                          vseq_ctx.cfg.ibi_target_addr,
                          vseq_ctx.cfg.ibi_basic_mdb),
                UVM_LOW)
    end
`else
    `uvm_fatal("IBI_RECOVERY_RAL_BUILD",
               "Target recovery cleanup requires SMC_USE_I3C_RAL")
`endif
`else
    `uvm_fatal("IBI_RECOVERY_RTL_BUILD",
               "Target recovery cleanup requires SMC_USE_I3C_RTL")
`endif
  endtask
endclass : smc_i3c_ibi_target_tx_recovery_cleanup_vseq

`endif // SMC_I3C_IBI_TARGET_TX_RECOVERY_CLEANUP_VSEQ_SV
