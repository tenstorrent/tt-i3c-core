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
// File        : smc_i3c_ibi_controller_rx_basic_test.sv
// Description : UVM test for I3C IBI controller receive.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-24
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_CONTROLLER_RX_BASIC_TEST_SV
`define SMC_I3C_IBI_CONTROLLER_RX_BASIC_TEST_SV

// First DUT-controller IBI test. A Device-mode UVM target emits one MDB-only
// IBI while the Controller starts a DAT-based transfer. The IBI wins against
// the broadcast header; the DUT must ACK it, enqueue one HCI IBI record and
// assert/clear the IBI threshold interrupt when software drains the record.
class smc_i3c_ibi_controller_rx_basic_test extends smc_i3c_ibi_base_test;
  `uvm_component_utils(smc_i3c_ibi_controller_rx_basic_test)

  function new(string name = "smc_i3c_ibi_controller_rx_basic_test",
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
      `uvm_fatal("IBI_CTRL_TEST_ROLE",
                 "smc_i3c_ibi_controller_rx_basic_test cannot run as DUT target")
    // Model an IBI-capable target that advertises MDB support. The first
    // Controller test provisions the dynamic address directly in DAT; DAA and
    // GETBCR negotiation are covered by later Controller-role scenarios.
    cfg.ibi_bcr = 8'h06;
    cfg.ibi_bcr_valid = 1'b1;
    // The vendored host-perspective monitor cannot decode a device-
    // initiated IBI that arbitrates into the Controller broadcast header: it
    // reports the transfer as an I2C write to a garbled address (observed
    // 0x6d) rather than an I3C read to the target DA, so no passive item can
    // ever correlate. The HCI status record, target-driver observation and
    // IBI interrupt remain the authoritative evidence for this mechanism.
    // Keep passive correlation off until a device-perspective passive monitor
    // is available; leaving it on withholds the actual item and turns a real
    // field check into an IBI_SB_TIMEOUT.
    cfg.require_ibi_passive_monitor_match = 1'b0;
  endfunction

  virtual function smc_peripherals_base_vseq create_vseq();
    return smc_i3c_ibi_controller_rx_basic_vseq::type_id::create("vseq");
  endfunction
endclass : smc_i3c_ibi_controller_rx_basic_test

`endif // SMC_I3C_IBI_CONTROLLER_RX_BASIC_TEST_SV
