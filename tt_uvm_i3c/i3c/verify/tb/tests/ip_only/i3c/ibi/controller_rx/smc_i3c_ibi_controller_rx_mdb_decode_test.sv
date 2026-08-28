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
// File        : smc_i3c_ibi_controller_rx_mdb_decode_test.sv
// Description : UVM test for Controller-RX MDB group decode.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-05
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_CONTROLLER_RX_MDB_DECODE_TEST_SV
`define SMC_I3C_IBI_CONTROLLER_RX_MDB_DECODE_TEST_SV

// UVM Target emits representative public-registry MDB groups. The independent
// Controller predictor/observer/scoreboard checks ACK, group classification,
// zero-extended IBI_ID, HCI record content and threshold IRQ behavior. The
// group-101 case is followed by a software-issued Private Read so the test does
// not violate the Pending Read Notification contract.
class smc_i3c_ibi_controller_rx_mdb_decode_test extends smc_i3c_ibi_base_test;
  `uvm_component_utils(smc_i3c_ibi_controller_rx_mdb_decode_test)

  function new(string name = "smc_i3c_ibi_controller_rx_mdb_decode_test",
               uvm_component parent = null);
    super.new(name, parent);
    dut_role = SMC_I3C_IBI_DUT_CONTROLLER;
  endfunction

  protected virtual function bit require_ibi_coverage_by_default();
    return 1'b1;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg.ibi_dut_role != SMC_I3C_IBI_DUT_CONTROLLER)
      `uvm_fatal("IBI_MDB_TEST_ROLE",
                 "smc_i3c_ibi_controller_rx_mdb_decode_test requires DUT Controller")
    cfg.ibi_bcr = 8'h06;
    cfg.ibi_bcr_valid = 1'b1;
    // The vendored monitor reports both a Target IBI and an ordinary Private
    // Read as the same generic BusOpRead and carries no explicit IBI ownership
    // marker. Keep it out of the verdict; the UVM Target-driver observation
    // and the independently read HCI record remain the correlation sources.
    cfg.require_ibi_passive_monitor_match = 1'b0;
  endfunction

  virtual function smc_peripherals_base_vseq create_vseq();
    return smc_i3c_ibi_controller_rx_mdb_decode_vseq::type_id::create("vseq");
  endfunction
endclass : smc_i3c_ibi_controller_rx_mdb_decode_test

`endif // SMC_I3C_IBI_CONTROLLER_RX_MDB_DECODE_TEST_SV
