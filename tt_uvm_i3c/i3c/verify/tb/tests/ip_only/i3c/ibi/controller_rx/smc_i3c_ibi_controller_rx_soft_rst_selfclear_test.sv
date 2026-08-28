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
// File        : smc_i3c_ibi_controller_rx_soft_rst_selfclear_test.sv
// Description : Defect reproduction for an inert HCI RESET_CONTROL.SOFT_RST.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-03
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_CONTROLLER_RX_SOFT_RST_SELFCLEAR_TEST_SV
`define SMC_I3C_IBI_CONTROLLER_RX_SOFT_RST_SELFCLEAR_TEST_SV

// Defect reproduction: HCI RESET_CONTROL.SOFT_RST does not self-clear. RTL
// inspection additionally shows that its hardware-write struct is tied to '0
// (hci.sv:442) and no block in src/ reads its value. That no-consumer finding is
// kept in the defect report because the local RDL does not define which
// configuration CSRs a working host-controller soft reset must restore.
//
// CSR only - no IBI, no bus traffic, no VIP sequence. The runtime verdict is
// deliberately narrow: FAIL (IBI_SOFT_RST_INERT) means the trigger remained set.
// A PASS means only that self-clear was implemented; downstream reset behavior
// still requires a contract-backed functional test.
//
// This test lives in the i3c_ibi_rtl_unsupported group, which is off by default
// because its expected outcome is FAIL; run it on demand with
// --group i3c_ibi_rtl_unsupported --include-off. It must not be added to a group
// whose PASS is used as a health signal, and it must not be waived.
//
// Once RTL implements SOFT_RST, add a separate mid-frame reset-quiescence test
// that resets a live IBI frame and checks behavior defined by the agreed HCI
// contract.
class smc_i3c_ibi_controller_rx_soft_rst_selfclear_test extends smc_i3c_ibi_base_test;
  `uvm_component_utils(smc_i3c_ibi_controller_rx_soft_rst_selfclear_test)

  function new(string name = "smc_i3c_ibi_controller_rx_soft_rst_selfclear_test",
               uvm_component parent = null);
    super.new(name, parent);
    dut_role = SMC_I3C_IBI_DUT_CONTROLLER;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg.ibi_dut_role != SMC_I3C_IBI_DUT_CONTROLLER)
      `uvm_fatal("IBI_SOFT_RST_TEST_ROLE",
                 "smc_i3c_ibi_controller_rx_soft_rst_selfclear_test cannot run as DUT target")

    // No IBI is raised, so the passive monitor has nothing to correlate.
    cfg.require_ibi_passive_monitor_match = 1'b0;
    // Negative scenario: zero IBI events is the requirement. Without this the
    // Controller scoreboard treats zero expected/actual events as "nothing was
    // checked" and fails the run unconditionally, masking the real verdict
    // (smc_i3c_ibi_controller_scoreboard.sv check_phase). Left enabled rather
    // than switched off so an unexpected IBI event would still be caught.
    cfg.ibi_expect_zero_events = 1'b1;

    `uvm_info(get_type_name(),
              "HCI SOFT_RST inertness reproduction configured: CSR-only, no bus traffic",
              UVM_LOW)
  endfunction

  virtual function smc_peripherals_base_vseq create_vseq();
    return smc_i3c_ibi_controller_rx_soft_rst_selfclear_vseq::type_id::create("vseq");
  endfunction
endclass : smc_i3c_ibi_controller_rx_soft_rst_selfclear_test

`endif // SMC_I3C_IBI_CONTROLLER_RX_SOFT_RST_SELFCLEAR_TEST_SV
