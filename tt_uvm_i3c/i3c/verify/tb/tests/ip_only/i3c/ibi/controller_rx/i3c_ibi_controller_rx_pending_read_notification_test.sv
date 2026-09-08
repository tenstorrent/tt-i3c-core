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
// File        : i3c_ibi_controller_rx_pending_read_notification_test.sv
// Description : UVM test for Controller-RX Pending Read Notification.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-05
//
// *****************************************************************************

`ifndef I3C_IBI_CONTROLLER_RX_PENDING_READ_NOTIFICATION_TEST_SV
`define I3C_IBI_CONTROLLER_RX_PENDING_READ_NOTIFICATION_TEST_SV

// A UVM Target sends a group-101 MDB and keeps four bytes ready. The test
// follows HC_CAPABILITIES.AUTO_COMMAND: a supported implementation must issue
// and coalesce the automatic Private Read; otherwise host software issues the
// required Private Read after validating the regular HCI IBI record and IRQ.
class i3c_ibi_controller_rx_pending_read_notification_test extends
    i3c_ibi_base_test;
  `uvm_component_utils(i3c_ibi_controller_rx_pending_read_notification_test)

  function new(
      string name = "i3c_ibi_controller_rx_pending_read_notification_test",
      uvm_component parent = null);
    super.new(name, parent);
    dut_role = I3C_IBI_DUT_CONTROLLER;
  endfunction

  protected virtual function bit require_ibi_coverage_by_default();
    return 1'b1;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg.ibi_dut_role != I3C_IBI_DUT_CONTROLLER)
      `uvm_fatal("IBI_PRN_TEST_ROLE",
                 "i3c_ibi_controller_rx_pending_read_notification_test requires DUT Controller")
    cfg.ibi_bcr = 8'h06;
    cfg.ibi_bcr_valid = 1'b1;
    // The generic passive monitor cannot distinguish the initial same-address
    // IBI read from the required Auto-Command Private Read. Enabling passive
    // correlation would incorrectly create a second IBI observation.
    cfg.require_ibi_passive_monitor_match = 1'b0;
  endfunction

  virtual function i3c_base_vseq create_vseq();
    return i3c_ibi_controller_rx_pending_read_notification_vseq::type_id::create(
      "vseq");
  endfunction
endclass : i3c_ibi_controller_rx_pending_read_notification_test

`endif // I3C_IBI_CONTROLLER_RX_PENDING_READ_NOTIFICATION_TEST_SV
