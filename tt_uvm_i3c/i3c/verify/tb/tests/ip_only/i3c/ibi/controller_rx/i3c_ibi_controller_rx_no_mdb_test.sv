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
// File        : i3c_ibi_controller_rx_no_mdb_test.sv
// Description : RTL-defect reproduction for an accepted IBI without an MDB.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-09-08
//
// *****************************************************************************

`ifndef I3C_IBI_CONTROLLER_RX_NO_MDB_TEST_SV
`define I3C_IBI_CONTROLLER_RX_NO_MDB_TEST_SV

// A matching DAT entry that does not reject the Target must accept a legal
// address-only IBI from a Target that advertises IBI capability but no MDB
// capability.  IBI_PAYLOAD is deliberately clear: it governs data following
// the header and must not turn a no-data IBI into an expected NACK.
class i3c_ibi_controller_rx_no_mdb_test extends i3c_ibi_base_test;
  `uvm_component_utils(i3c_ibi_controller_rx_no_mdb_test)

  function new(string name = "i3c_ibi_controller_rx_no_mdb_test",
               uvm_component parent = null);
    super.new(name, parent);
    dut_role = I3C_IBI_DUT_CONTROLLER;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg.ibi_dut_role != I3C_IBI_DUT_CONTROLLER)
      `uvm_fatal("IBI_NO_MDB_TEST_ROLE",
                 "i3c_ibi_controller_rx_no_mdb_test requires DUT Controller")

    cfg.ibi_bcr = '0;
    cfg.ibi_bcr[I3C_BCR_IBI_CAPABLE_BIT] = 1'b1;
    cfg.ibi_bcr[I3C_BCR_MDB_CAPABLE_BIT] = 1'b0;
    cfg.ibi_bcr_valid = 1'b1;

    // The known host-perspective passive-monitor limitation for a
    // device-initiated IBI applies to all Controller-RX tests.  The active
    // Target observation, HCI observer and Controller scoreboard remain on.
    cfg.require_ibi_passive_monitor_match = 1'b0;
  endfunction

  virtual function i3c_base_vseq create_vseq();
    return i3c_ibi_controller_rx_no_mdb_vseq::type_id::create("vseq");
  endfunction
endclass : i3c_ibi_controller_rx_no_mdb_test

`endif // I3C_IBI_CONTROLLER_RX_NO_MDB_TEST_SV
