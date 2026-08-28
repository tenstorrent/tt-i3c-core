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
// File        : smc_i3c_ibi_target_tx_retry_arbitration_test.sv
// Description : UVM test for bounded Target IBI retry/re-arbitration.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-04
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_TARGET_TX_RETRY_ARBITRATION_TEST_SV
`define SMC_I3C_IBI_TARGET_TX_RETRY_ARBITRATION_TEST_SV

class smc_i3c_ibi_target_tx_retry_arbitration_test extends smc_i3c_ibi_base_test;
  `uvm_component_utils(smc_i3c_ibi_target_tx_retry_arbitration_test)

  function new(string name = "smc_i3c_ibi_target_tx_retry_arbitration_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  protected virtual function bit require_ibi_coverage_by_default();
    return 1'b1;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    int unsigned retry_plusarg;

    super.build_phase(phase);
    if (!$value$plusargs("IBI_RETRY_COUNT=%0d", retry_plusarg))
      cfg.ibi_retry_count = 2;
    cfg.ibi_retry_tracking = 1'b1;
  endfunction

  virtual function smc_peripherals_base_vseq create_vseq();
    return smc_i3c_ibi_target_tx_retry_arbitration_vseq::type_id::create("vseq");
  endfunction
endclass : smc_i3c_ibi_target_tx_retry_arbitration_test

`endif // SMC_I3C_IBI_TARGET_TX_RETRY_ARBITRATION_TEST_SV
