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
// File        : i3c_ibi_target_tx_retry_limit_test.sv
// Description : Focused DUT-Target bounded retry-limit compatibility test.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-09-08
//
// *****************************************************************************
`ifndef I3C_IBI_TARGET_TX_RETRY_LIMIT_TEST_SV
`define I3C_IBI_TARGET_TX_RETRY_LIMIT_TEST_SV

// This public identity is intentionally single-requester.  It preserves the
// focused retry-limit run without claiming multi-target arbitration coverage.
class i3c_ibi_target_tx_retry_limit_test extends
    i3c_ibi_target_tx_retry_arbitration_test;
  `uvm_component_utils(i3c_ibi_target_tx_retry_limit_test)
  function new(string name = "i3c_ibi_target_tx_retry_limit_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  virtual function i3c_base_vseq create_vseq();
    return i3c_ibi_target_tx_retry_arbitration_vseq::type_id::create("vseq");
  endfunction
endclass

`endif
