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
// File        : smc_i3c_ibi_controller_rx_reset_flush_test.sv
// Description : UVM test for the HCI IBI queue reset (IBI_QUEUE_RST).
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-06
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_CONTROLLER_RX_RESET_FLUSH_TEST_SV
`define SMC_I3C_IBI_CONTROLLER_RX_RESET_FLUSH_TEST_SV

// Implements the Controller-RX half of test plan row 04_Tests!r24
// (smc_i3c_ibi_reset_flush_test, "HCI IBI FIFO/status/IRQ cleanup on
// Controller"). The Target-TX half of that row is not implemented here.
//
// HCI IBI queue reset. One MDB-only IBI is completed so that a record sits in
// the HCI IBI FIFO, then RESET_CONTROL.IBI_QUEUE_RST is asserted and the
// FIFO-scoped effects are checked: the trigger self-clears (which the RTL only
// does once the FIFO reports empty), the IBI threshold status drops, and the
// IRQ follows it down.
//
// Scope is deliberately narrow. IBI_QUEUE_RST reaches only the HCI IBI
// read_queue (hci.sv:428) and touches neither the Controller FSM nor the bus,
// so this test asserts nothing about frame abort, bus release or in-flight
// transactions. The mid-frame variant of that scenario needs a working
// SOFT_RST, which this RTL does not have - see
// smc_i3c_ibi_controller_rx_soft_rst_selfclear_test.
//
// The Controller checker remains enabled. Its AXI reset observer retires the
// pending expected transaction as "flushed" without reading PIO_INTR.IBI_PORT,
// so the test preserves the record until reset while still checking that no
// stale transaction survives in the predictor/observer/scoreboard pipeline.
// Descriptor fields are not compared because a destructive FIFO pop is outside
// this scenario; receive/content tests retain that responsibility.
//
// Coverage: require_ibi_coverage_by_default() stays 0. The record is never
// popped, so the queue/IRQ completion samples this scenario would need do not
// occur. Keep the test out of the +IBI_REQUIRE_COV regression group.
class smc_i3c_ibi_controller_rx_reset_flush_test extends smc_i3c_ibi_base_test;
  `uvm_component_utils(smc_i3c_ibi_controller_rx_reset_flush_test)

  function new(string name = "smc_i3c_ibi_controller_rx_reset_flush_test",
               uvm_component parent = null);
    super.new(name, parent);
    dut_role = SMC_I3C_IBI_DUT_CONTROLLER;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg.ibi_dut_role != SMC_I3C_IBI_DUT_CONTROLLER)
      `uvm_fatal("IBI_QUEUE_CLEAR_TEST_ROLE",
                 "smc_i3c_ibi_controller_rx_reset_flush_test cannot run as DUT target")

    // IBI-capable target advertising MDB support, provisioned directly in DAT,
    // matching the other Controller-role scenarios.
    cfg.ibi_bcr = 8'h06;
    cfg.ibi_bcr_valid = 1'b1;
    // The vendored host-perspective monitor cannot decode a device-initiated
    // IBI that arbitrates into the Controller broadcast header.
    cfg.require_ibi_passive_monitor_match = 1'b0;
    `uvm_info(get_type_name(),
              $sformatf("Controller IBI queue-clear configured: DA=0x%02h MDB=0x%02h",
                        cfg.ibi_target_addr, cfg.ibi_basic_mdb),
              UVM_LOW)
  endfunction

  virtual function smc_peripherals_base_vseq create_vseq();
    return smc_i3c_ibi_controller_rx_reset_flush_vseq::type_id::create("vseq");
  endfunction
endclass : smc_i3c_ibi_controller_rx_reset_flush_test

`endif // SMC_I3C_IBI_CONTROLLER_RX_RESET_FLUSH_TEST_SV
