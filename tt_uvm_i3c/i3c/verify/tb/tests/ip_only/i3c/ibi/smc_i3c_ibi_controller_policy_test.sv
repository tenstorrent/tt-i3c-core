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
// File        : smc_i3c_ibi_controller_policy_test.sv
// Description : UVM test for I3C IBI controller policy.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-25
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_CONTROLLER_POLICY_TEST_SV
`define SMC_I3C_IBI_CONTROLLER_POLICY_TEST_SV

// DUT-controller DAT policy test. A Device-mode UVM target requests four IBIs
// against matched-accept, matched-reject, payload-disabled and no-match DAT
// configurations. Every attempt must produce one HCI status descriptor and
// IRQ; accepted traffic carries MDB/payload, while NACK status records must
// have DATA_LENGTH zero and commit no payload bytes.
//
// KNOWN RTL LIMITATIONS (originally reproduced on core ff1626f3; retain until
// revalidated on the current a6361105 pin; an RTL-owner task). The policy
// checks below are reported as UVM_ERROR, not
// UVM_FATAL, so the test runs every case to completion instead of aborting on
// the first blockage. Per verification policy these errors are reported, never
// waived.
//   1. No-match IBI is ACKed instead of NACKed. The ACK/NACK decision
//      (flow_active.sv:1558 ibi_abort) uses the DAT entry pre-loaded by the
//      arbitration-window private write, not an address-correlated lookup; the
//      RLT->DAT reverse lookup resolves after the ACK bit, so an IBI whose
//      address has no matching DAT entry is accepted. Same root cause as the
//      idle-bus IBI NACK bug (doc/i3c_controller_ibi_idle_nack_analysis.md).
//      => the "DAT no-match" case fails IBI_CTRL_POLICY_RESPONSE.
//   2. Only the first IBI in a simulation is serviced. From the 2nd IBI on,
//      the controller accepts the arbitration-window private write into its
//      command queue but never drives START/SCL for it, so the Device-mode
//      driver blocks in address arbitration and the target sequence never
//      completes (observed in run test_20260725_144041: DAT-accept passes,
//      DAT-reject then times out). Root cause is the same stale DAT/RLT
//      pipeline / command-FSM context as bug 1, not cleared by draining the
//      bus wires. Worse, the vendored I3C Device driver blocks inside
//      super.drive_device_item() on the un-serviced arbitration and a
//      sequence kill() cannot free it, so it never dequeues the next case's
//      item and no later case can arm. The vseq bounds BOTH the arm wait and
//      the completion wait (POLICY_TARGET_TIMEOUT_CYCLES) so each expected
//      hang costs ~200 us and the simulation always terminates. The vseq has
//      two source-level modes (no plusarg):
//        RUN_ALL_IN_ONE_SEQ=1 (current default) chains all four cases in one
//          sim as a diagnostic. Case 1 (accept) passes; cases 2-4 fail
//          NON-FATALLY here (A.3 wedge), and the controller scoreboard summary
//          counts them ("Cases launched"/"Cases incomplete", plus an
//          "incomplete cases" mismatch), so it cannot silently report PASS.
//        RUN_ALL_IN_ONE_SEQ=0 runs one source-selected ACTIVE_POLICY_CASE
//          (1..4) as the sim's only IBI, so each case reports its real result
//          from a clean reset: cases 1-3 pass, case 4 (no-match) is the bug-1
//          known-fail. This is the structural fit for the DV single-record
//          constraint; use it once the RTL services multiple IBIs per sim.
class smc_i3c_ibi_controller_policy_test extends
    smc_i3c_ibi_controller_receive_test;
  `uvm_component_utils(smc_i3c_ibi_controller_policy_test)

  function new(string name = "smc_i3c_ibi_controller_policy_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function smc_peripherals_base_vseq create_vseq();
    return smc_i3c_ibi_controller_policy_vseq::type_id::create("vseq");
  endfunction
endclass : smc_i3c_ibi_controller_policy_test

`endif // SMC_I3C_IBI_CONTROLLER_POLICY_TEST_SV
