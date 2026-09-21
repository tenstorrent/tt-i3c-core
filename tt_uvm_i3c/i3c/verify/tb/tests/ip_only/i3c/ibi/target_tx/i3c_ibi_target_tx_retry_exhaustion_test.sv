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
// File        : i3c_ibi_target_tx_retry_exhaustion_test.sv
// Description : Finite Target IBI retry-limit exhaustion test.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-18
//
// *****************************************************************************

`ifndef I3C_IBI_TARGET_TX_RETRY_EXHAUSTION_TEST_SV
`define I3C_IBI_TARGET_TX_RETRY_EXHAUSTION_TEST_SV

class i3c_ibi_target_tx_retry_exhaustion_test extends
    i3c_ibi_target_tx_retry_arbitration_test;
  `uvm_component_utils(i3c_ibi_target_tx_retry_exhaustion_test)

  function new(string name = "i3c_ibi_target_tx_retry_exhaustion_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg.ibi_retry_exhaustion = 1'b1;
  endfunction
endclass : i3c_ibi_target_tx_retry_exhaustion_test

`endif // I3C_IBI_TARGET_TX_RETRY_EXHAUSTION_TEST_SV
