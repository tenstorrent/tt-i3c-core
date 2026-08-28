// *****************************************************************************
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 VNCHIP LABS
//
// File        : smc_i3c_ibi_controller_rx_no_mdb_test.sv
// Description : RTL-defect reproduction for an accepted IBI without an MDB.
// *****************************************************************************

`ifndef SMC_I3C_IBI_CONTROLLER_RX_NO_MDB_TEST_SV
`define SMC_I3C_IBI_CONTROLLER_RX_NO_MDB_TEST_SV

// A matching DAT entry that does not reject the Target must accept a legal
// address-only IBI from a Target that advertises IBI capability but no MDB
// capability.  IBI_PAYLOAD is deliberately clear: it governs data following
// the header and must not turn a no-data IBI into an expected NACK.
class smc_i3c_ibi_controller_rx_no_mdb_test extends smc_i3c_ibi_base_test;
  `uvm_component_utils(smc_i3c_ibi_controller_rx_no_mdb_test)

  function new(string name = "smc_i3c_ibi_controller_rx_no_mdb_test",
               uvm_component parent = null);
    super.new(name, parent);
    dut_role = SMC_I3C_IBI_DUT_CONTROLLER;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg.ibi_dut_role != SMC_I3C_IBI_DUT_CONTROLLER)
      `uvm_fatal("IBI_NO_MDB_TEST_ROLE",
                 "smc_i3c_ibi_controller_rx_no_mdb_test requires DUT Controller")

    cfg.ibi_bcr = '0;
    cfg.ibi_bcr[SMC_I3C_BCR_IBI_CAPABLE_BIT] = 1'b1;
    cfg.ibi_bcr[SMC_I3C_BCR_MDB_CAPABLE_BIT] = 1'b0;
    cfg.ibi_bcr_valid = 1'b1;

    // The known host-perspective passive-monitor limitation for a
    // device-initiated IBI applies to all Controller-RX tests.  The active
    // Target observation, HCI observer and Controller scoreboard remain on.
    cfg.require_ibi_passive_monitor_match = 1'b0;
  endfunction

  virtual function smc_peripherals_base_vseq create_vseq();
    return smc_i3c_ibi_controller_rx_no_mdb_vseq::type_id::create("vseq");
  endfunction
endclass : smc_i3c_ibi_controller_rx_no_mdb_test

`endif // SMC_I3C_IBI_CONTROLLER_RX_NO_MDB_TEST_SV
