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
// File        : i3c_ibi_target_tx_partial_recovery_test.sv
// Description : Target IBI partial-data protocol-error and recovery test.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-18
//
// *****************************************************************************

`ifndef I3C_IBI_TARGET_TX_PARTIAL_RECOVERY_TEST_SV
`define I3C_IBI_TARGET_TX_PARTIAL_RECOVERY_TEST_SV

class i3c_ibi_target_tx_partial_recovery_test extends
    i3c_ibi_target_tx_mdb_payload_test;
  `uvm_component_utils(i3c_ibi_target_tx_partial_recovery_test)

  function new(string name = "i3c_ibi_target_tx_partial_recovery_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg.ibi_expect_partial_data = 1'b1;
    // The Host returns its two-byte request including the abort boundary; the
    // passive monitor publishes the one fully completed MDB byte before it.
    cfg.ibi_partial_host_rx_bytes = 2;
    cfg.ibi_partial_passive_bytes = 1;
    cfg.has_ibi_recovery_checker = 1'b1;
  endfunction
endclass : i3c_ibi_target_tx_partial_recovery_test

`endif // I3C_IBI_TARGET_TX_PARTIAL_RECOVERY_TEST_SV
