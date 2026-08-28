// *****************************************************************************
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 VNCHIP LABS
//
// File        : smc_i3c_ibi_controller_rx_no_mdb_vseq.sv
// Description : Requirement-driven no-MDB IBI Controller-RX reproduction.
// *****************************************************************************

`ifndef SMC_I3C_IBI_CONTROLLER_RX_NO_MDB_VSEQ_SV
`define SMC_I3C_IBI_CONTROLLER_RX_NO_MDB_VSEQ_SV

class smc_i3c_ibi_controller_rx_no_mdb_vseq extends smc_i3c_ibi_base_vseq;
  `uvm_object_utils(smc_i3c_ibi_controller_rx_no_mdb_vseq)

  function new(string name = "smc_i3c_ibi_controller_rx_no_mdb_vseq");
    super.new(name);
  endfunction

  virtual task body();
    super.body();
    if (!vseq_ctx.cfg.has_rtl)
      `uvm_fatal("IBI_NO_MDB_MODE",
                 "Positive no-MDB reproduction requires DUT_MODE=rtl")
    if (vseq_ctx.cfg.ibi_dut_role != SMC_I3C_IBI_DUT_CONTROLLER)
      `uvm_fatal("IBI_NO_MDB_ROLE",
                 "Positive no-MDB reproduction requires DUT-controller role")
    if (!vseq_ctx.cfg.ibi_bcr[BCR_IBI_CAPABLE_BIT] ||
        vseq_ctx.cfg.ibi_bcr[BCR_MDB_CAPABLE_BIT])
      `uvm_fatal("IBI_NO_MDB_BCR",
                 $sformatf("Expected BCR IBI=1/MDB=0, got 0x%02h",
                           vseq_ctx.cfg.ibi_bcr))

`ifdef SMC_USE_I3C_RTL
`ifdef SMC_USE_I3C_RAL
    begin
      smc_i3c_controller_hci_helper #(TB_ADDR_WIDTH, TB_DATA_WIDTH)
        hci_helper;
      smc_i3c_target_send_ibi_seq target_seq;
      bit [31:0] interrupt_status;
      bit [31:0] descriptor;
      byte unsigned hci_data[$];
      bit target_transfer_done;
      int unsigned completion_before;
      int unsigned mismatch_before;
      int unsigned expected_before;
      int unsigned actual_before;

      hci_helper = vseq_ctx.i3c_controller_hci_helper;
      if (hci_helper == null)
        `uvm_fatal("IBI_NO_MDB_HELPER", "Controller HCI helper is not available")

      completion_before = vseq_ctx.cfg.ibi_sb_completion_count;
      mismatch_before = vseq_ctx.cfg.ibi_sb_mismatch_count;
      expected_before = vseq_ctx.cfg.ibi_controller_expected_events;
      actual_before = vseq_ctx.cfg.ibi_controller_actual_events;

      // Initialize the Controller transport, then overwrite the matching DAT
      // entry with IBI_PAYLOAD=0.  This is an HCI programming operation only;
      // the external Target, not a Controller transfer command, owns START.
      hci_helper.initialize_controller_ibi(
        vseq_ctx.cfg.ibi_target_addr,
        vseq_ctx.cfg.ibi_controller_dat_index,
        this);
      hci_helper.program_dat_entry(
        vseq_ctx.cfg.ibi_controller_dat_index,
        vseq_ctx.cfg.ibi_target_addr, '0, 1'b0, 1'b0, this);
      wait_bus_idle("wait for an idle bus before positive no-MDB IBI");
      hci_helper.wait_bus_available(this);
      wait_irq(1'b0, "verify no-MDB IBI IRQ initially low");

      vseq_ctx.cfg.vif.i3c_controller_expected_addr =
        vseq_ctx.cfg.ibi_target_addr;
      vseq_ctx.cfg.vif.i3c_controller_expected_ack = 1'b1;
      vseq_ctx.cfg.ibi_requester_count = 1;
      vseq_ctx.cfg.ibi_arb_outcome = 2'd0; // sole requester
      vseq_ctx.cfg.ibi_bus_state = 2'd0;   // idle/bus available

      target_seq = smc_i3c_target_send_ibi_seq::type_id::create(
        "no_mdb_target_seq");
      target_seq.target_addr = vseq_ctx.cfg.ibi_target_addr;
      target_seq.mdb_present = 1'b0;
      target_seq.allow_no_mdb_ibi = 1'b1;
      target_seq.payload.delete();
      target_seq.start_on_idle = 1'b1;

      target_transfer_done = 1'b0;
      fork : target_ibi_driver
        begin
          target_seq.start(vseq_ctx.i3c_sqr);
          target_transfer_done = 1'b1;
        end
      join_none

      fork : target_ibi_timeout_guard
        begin
          wait (target_transfer_done);
        end
        begin
          repeat (vseq_ctx.cfg.ibi_timeout_cycles)
            @(posedge vseq_ctx.cfg.vif.clk);
          if (!target_transfer_done)
            `uvm_fatal("IBI_NO_MDB_BUS_TIMEOUT",
                       "Timed out waiting for the address-only target IBI")
        end
      join_any
      disable target_ibi_timeout_guard;
      disable target_ibi_driver;
      if (!target_transfer_done)
        `uvm_fatal("IBI_NO_MDB_BUS", "Address-only target IBI did not complete")

      if (!target_seq.observed_ack) begin
        `uvm_error("IBI_NO_MDB_UNEXPECTED_NACK",
                   $sformatf({"Valid no-MDB IBI was NACKed: DA=0x%02h BCR=0x%02h ",
                              "DAT(match=1 reject=0 payload=0) expected_ACK=1 ",
                              "observed_ACK=0 stimulus_bytes=%0d"},
                             vseq_ctx.cfg.ibi_target_addr,
                             vseq_ctx.cfg.ibi_bcr,
                             target_seq.payload.size()))
      end
      else begin
        // The existing Controller HCI checker defines the delivered record
        // transport: an accepted zero-byte IBI carries a status descriptor,
        // no data DWORDs, and then drains/clears normally.
        wait_irq(1'b1, "wait for accepted no-MDB IBI IRQ");
        hci_helper.read_ibi_status(interrupt_status, this);
        if (!interrupt_status[2])
          `uvm_error("IBI_NO_MDB_IRQ_STATUS",
                     $sformatf("IBI_STATUS_THLD_STAT is low: 0x%08h",
                               interrupt_status))
        hci_helper.read_ibi_record(descriptor, hci_data, this);
        if (descriptor[15:8] !== {vseq_ctx.cfg.ibi_target_addr, 1'b1})
          `uvm_error("IBI_NO_MDB_HCI_ID",
                     $sformatf("Expected IBI_ID=0x%02h got descriptor=0x%08h",
                               {vseq_ctx.cfg.ibi_target_addr, 1'b1}, descriptor))
        if ((descriptor[7:0] != 0) || (hci_data.size() != 0))
          `uvm_error("IBI_NO_MDB_HCI_DATA",
                     $sformatf("Accepted no-MDB IBI committed DATA_LENGTH=%0d bytes=%0d",
                               descriptor[7:0], hci_data.size()))
        if (descriptor[31] || descriptor[30])
          `uvm_error("IBI_NO_MDB_HCI_STATUS",
                     $sformatf("Accepted no-MDB IBI has failure/error descriptor=0x%08h",
                               descriptor))
        wait_scoreboard_completion(
          completion_before + 1,
          "wait for no-MDB Controller scoreboard completion");
        wait_irq(1'b0, "wait for no-MDB IBI IRQ clear after drain");
        hci_helper.read_ibi_status(interrupt_status, this);
        if (interrupt_status[2])
          `uvm_error("IBI_NO_MDB_IRQ_CLEAR",
                     $sformatf("IBI threshold status remained set: 0x%08h",
                               interrupt_status))
      end

      if (vseq_ctx.cfg.ibi_sb_mismatch_count != mismatch_before)
        `uvm_error("IBI_NO_MDB_SCOREBOARD",
                   $sformatf("No-MDB IBI added scoreboard mismatches=%0d",
                             vseq_ctx.cfg.ibi_sb_mismatch_count -
                             mismatch_before))
      if (((vseq_ctx.cfg.ibi_controller_expected_events - expected_before) != 1) ||
          ((vseq_ctx.cfg.ibi_controller_actual_events - actual_before) != 1))
        `uvm_error("IBI_NO_MDB_EVENT_COUNT",
                   $sformatf("Expected one Controller event, got expected/actual=%0d/%0d",
                             vseq_ctx.cfg.ibi_controller_expected_events - expected_before,
                             vseq_ctx.cfg.ibi_controller_actual_events - actual_before))
    end
`else
    `uvm_fatal("IBI_NO_MDB_RAL_BUILD",
               "Positive no-MDB reproduction requires SMC_USE_I3C_RAL")
`endif
`else
    `uvm_fatal("IBI_NO_MDB_RTL_BUILD",
               "Positive no-MDB reproduction requires SMC_USE_I3C_RTL")
`endif
  endtask
endclass : smc_i3c_ibi_controller_rx_no_mdb_vseq

`endif // SMC_I3C_IBI_CONTROLLER_RX_NO_MDB_VSEQ_SV
