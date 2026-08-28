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
// File        : smc_i3c_ibi_target_tx_recovery_cleanup_test.sv
// Description : Target-role IBI reset cleanup and forward-progress test.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-06
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_TARGET_TX_RECOVERY_CLEANUP_TEST_SV
`define SMC_I3C_IBI_TARGET_TX_RECOVERY_CLEANUP_TEST_SV

class smc_i3c_ibi_target_tx_recovery_cleanup_test extends smc_i3c_ibi_base_test;
  `uvm_component_utils(smc_i3c_ibi_target_tx_recovery_cleanup_test)

  function new(string name = "smc_i3c_ibi_target_tx_recovery_cleanup_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  protected virtual function bit require_ibi_coverage_by_default();
    return 1'b1;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg.ibi_dut_role != SMC_I3C_IBI_DUT_TARGET)
      `uvm_fatal("IBI_RECOVERY_TEST_ROLE",
                 "smc_i3c_ibi_target_tx_recovery_cleanup_test cannot run as DUT controller")
    cfg.has_ibi_recovery_checker = 1'b1;
    cfg.require_ibi_passive_monitor_match = 1'b1;
  endfunction

  virtual function smc_peripherals_base_vseq create_vseq();
    return smc_i3c_ibi_target_tx_recovery_cleanup_vseq::type_id::create("vseq");
  endfunction
endclass : smc_i3c_ibi_target_tx_recovery_cleanup_test

`endif // SMC_I3C_IBI_TARGET_TX_RECOVERY_CLEANUP_TEST_SV
