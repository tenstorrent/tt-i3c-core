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
// File        : smc_i3c_ibi_controller_rx_recovery_cleanup_vseq.sv
// Description : Controller-role IBI FIFO cleanup and forward-progress sequence.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-06
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_CONTROLLER_RX_RECOVERY_CLEANUP_VSEQ_SV
`define SMC_I3C_IBI_CONTROLLER_RX_RECOVERY_CLEANUP_VSEQ_SV

class smc_i3c_ibi_controller_rx_recovery_cleanup_vseq extends
    smc_i3c_ibi_base_vseq;
  `uvm_object_utils(smc_i3c_ibi_controller_rx_recovery_cleanup_vseq)

  function new(string name = "smc_i3c_ibi_controller_rx_recovery_cleanup_vseq");
    super.new(name);
  endfunction

  virtual task body();
    super.body();
    if (!vseq_ctx.cfg.has_rtl)
      `uvm_fatal("IBI_CTRL_RECOVERY_MODE",
                 "Controller recovery cleanup requires DUT_MODE=rtl")
    if (vseq_ctx.cfg.ibi_dut_role != SMC_I3C_IBI_DUT_CONTROLLER)
      `uvm_fatal("IBI_CTRL_RECOVERY_ROLE",
                 "Controller recovery cleanup requires DUT-controller role")

`ifdef SMC_USE_I3C_RTL
`ifdef SMC_USE_I3C_RAL
    begin
      smc_i3c_ibi_controller_rx_reset_flush_vseq reset_flush_vseq;
      smc_i3c_ibi_controller_rx_basic_vseq followup_vseq;
      smc_i3c_ibi_recovery_checker recovery_checker;
      bit completed;
      bit recovered;
      int unsigned recovery_samples_before;

      recovery_checker = vseq_ctx.i3c_ibi_recovery_checker;
      if (recovery_checker == null)
        `uvm_fatal("IBI_CTRL_RECOVERY_CHECKER",
                   "Controller recovery checker is unavailable")

      recovery_samples_before = vseq_ctx.cfg.ibi_cov_recovery_samples;
      recovery_checker.arm_recovery(IBI_ERR_RESET_FLUSH, 1'b1, 1'b1);

      reset_flush_vseq =
        smc_i3c_ibi_controller_rx_reset_flush_vseq::type_id::create(
          "reset_flush_vseq");
      reset_flush_vseq.vseq_ctx = vseq_ctx;
      reset_flush_vseq.start(null);

      followup_vseq = smc_i3c_ibi_controller_rx_basic_vseq::type_id::create(
        "followup_vseq");
      followup_vseq.vseq_ctx = vseq_ctx;
      followup_vseq.start(null);

      recovery_checker.wait_for_result(
        vseq_ctx.cfg.ibi_timeout_cycles, completed, recovered);
      if (!completed || !recovered)
        `uvm_fatal("IBI_CTRL_RECOVERY_RESULT",
                   "Controller IBI FIFO cleanup did not restore forward progress")
      if ((vseq_ctx.cfg.ibi_cov_recovery_samples -
           recovery_samples_before) != 1)
        `uvm_fatal("IBI_CTRL_RECOVERY_COVERAGE",
                   "Controller recovery produced an invalid number of recovery samples")

      `uvm_info("IBI_CTRL_RECOVERY_PASS",
                $sformatf("Controller IBI FIFO cleanup passed: DA=0x%02h MDB=0x%02h",
                          vseq_ctx.cfg.ibi_target_addr,
                          vseq_ctx.cfg.ibi_basic_mdb),
                UVM_LOW)
    end
`else
    `uvm_fatal("IBI_CTRL_RECOVERY_RAL_BUILD",
               "Controller recovery cleanup requires SMC_USE_I3C_RAL")
`endif
`else
    `uvm_fatal("IBI_CTRL_RECOVERY_RTL_BUILD",
               "Controller recovery cleanup requires SMC_USE_I3C_RTL")
`endif
  endtask
endclass : smc_i3c_ibi_controller_rx_recovery_cleanup_vseq

`endif // SMC_I3C_IBI_CONTROLLER_RX_RECOVERY_CLEANUP_VSEQ_SV
