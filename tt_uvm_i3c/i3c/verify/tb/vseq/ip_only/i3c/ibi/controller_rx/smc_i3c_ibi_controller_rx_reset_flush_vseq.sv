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
// File        : smc_i3c_ibi_controller_rx_reset_flush_vseq.sv
// Description : Virtual sequence for HCI IBI queue reset (IBI_QUEUE_RST).
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-06
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_CONTROLLER_RX_RESET_FLUSH_VSEQ_SV
`define SMC_I3C_IBI_CONTROLLER_RX_RESET_FLUSH_VSEQ_SV

// HCI IBI queue reset, scoped to what RESET_CONTROL.IBI_QUEUE_RST actually
// does in this RTL.
//
// Scope
// -----
// hci_ibi_rst is read from the CSR at hci.sv:390 and reaches exactly one
// destination: the reg_rst_i port of the read_queue holding the HCI IBI FIFO
// (hci.sv:428). Inside that queue it drives fifo_clr (read_queue.sv:58) and
// clears the read-port registers (read_queue.sv:122-125). It touches nothing
// else - not the Controller flow FSM, not the bus, not any in-flight transfer.
//
// Therefore this sequence asserts only FIFO-scoped properties:
//   - the trigger self-clears, and
//   - the queue-derived status stops indicating a pending record.
// It deliberately makes no claim about frame abort, bus release or FSM state,
// and it does not use the passive phase tracker: the IBI record is not written
// until the frame ends, so resetting mid-frame would act on an empty FIFO and
// every bus phase would give the same result.
//
// Why the self-clear is the primary witness
// -----------------------------------------
// read_queue.sv:112 drives reg_rst_we_o <= reg_rst_i && empty_o, so hardware
// only writes the trigger back to zero once the FIFO has actually drained. The
// self-clear is not a bookkeeping artefact - it is the RTL reporting that the
// queue is empty, and it is the only such report visible through the CSR map.
// IBI_STATUS_THLD_STAT is checked as an independent second witness.
//
// Descriptor-content comparison is out of scope here because the scoreboard's
// actual event is built from a destructive AXI read of PIO_INTR.IBI_PORT. The
// checker remains enabled and observes RESET_CONTROL directly: it retires the
// pending expected event as flushed, while receive/content tests retain IBI
// descriptor-field checking.
class smc_i3c_ibi_controller_rx_reset_flush_vseq extends smc_i3c_ibi_base_vseq;
  `uvm_object_utils(smc_i3c_ibi_controller_rx_reset_flush_vseq)

  function new(string name = "smc_i3c_ibi_controller_rx_reset_flush_vseq");
    super.new(name);
  endfunction

  protected virtual function string scenario_name();
    return "Controller HCI IBI queue clear (IBI_QUEUE_RST)";
  endfunction

  protected virtual function void configure_target_ibi(
      smc_i3c_target_send_ibi_seq target_seq);
    target_seq.target_addr = vseq_ctx.cfg.ibi_target_addr;
    target_seq.mdb_present = 1'b1;
    target_seq.mdb = vseq_ctx.cfg.ibi_basic_mdb;
    target_seq.payload.delete();
    // Ride the Controller-opened address window, as the other Controller-role
    // scenarios do. The idle-origin path NACKs by construction on this RTL.
    target_seq.start_on_idle = 1'b0;
  endfunction

`ifdef SMC_USE_I3C_RTL
`ifdef SMC_USE_I3C_RAL
  // Assert IBI_QUEUE_RST and wait for the hardware write-back. Reported with
  // `uvm_error rather than `uvm_fatal so one run surfaces both this and the
  // threshold-status result.
  protected task clear_ibi_queue(smc_i3c_ral_model ral, output bit self_cleared);
    uvm_reg_data_t field_value;

    self_cleared = 1'b0;
    // RESET_CONTROL packs six independent triggers into one register, so only
    // the field's own byte lane may be written; write_field() could dispatch to
    // a parent read-modify-write and replay a neighbouring trigger.
    write_action_field(ral.I3CBase.RESET_CONTROL.IBI_QUEUE_RST, 1,
                       "assert HCI IBI queue reset");

    for (int unsigned poll = 0;
         poll < vseq_ctx.cfg.ibi_timeout_cycles; poll++) begin
      read_field(ral.I3CBase.RESET_CONTROL.IBI_QUEUE_RST, field_value,
                 "wait for HCI IBI_QUEUE_RST self-clear");
      if (field_value == 0) begin
        self_cleared = 1'b1;
        return;
      end
      @(posedge vseq_ctx.cfg.vif.clk);
    end
    `uvm_error("IBI_QUEUE_CLEAR_NO_SELF_CLEAR",
               "RESET_CONTROL.IBI_QUEUE_RST did not self-clear, so the HCI IBI FIFO never reported empty (read_queue.sv:112)")
  endtask
`endif
`endif

  virtual task body();
    super.body();
    if (!vseq_ctx.cfg.has_rtl)
      `uvm_fatal("IBI_QUEUE_CLEAR_MODE",
                 "Controller IBI queue-clear test requires DUT_MODE=rtl")
    if (vseq_ctx.cfg.ibi_dut_role != SMC_I3C_IBI_DUT_CONTROLLER)
      `uvm_fatal("IBI_QUEUE_CLEAR_ROLE",
                 "Controller IBI queue-clear vseq requires DUT-controller role")

`ifdef SMC_USE_I3C_RTL
`ifdef SMC_USE_I3C_RAL
    begin
      smc_i3c_target_send_ibi_seq target_seq;
      smc_i3c_controller_hci_helper #(TB_ADDR_WIDTH, TB_DATA_WIDTH)
        hci_helper;
      smc_i3c_ral_model ral;
      uvm_event target_armed_event;
      bit [TB_DATA_WIDTH-1:0] status_before;
      bit [TB_DATA_WIDTH-1:0] status_after;
      bit target_transfer_done;
      bit self_cleared;

      ral = get_i3c_ral_model();
      hci_helper = vseq_ctx.i3c_controller_hci_helper;
      if (hci_helper == null)
        `uvm_fatal("IBI_QUEUE_CLEAR_HCI_HELPER",
                   "Controller HCI helper is not available")
      if (vseq_ctx.i3c_sqr == null)
        `uvm_fatal("IBI_QUEUE_CLEAR_SQR",
                   "I3C target sequencer is not available")

      // ---------------------------------------------------------------
      // Stage 1: put one real record into the HCI IBI queue.
      // ---------------------------------------------------------------
      hci_helper.initialize_controller_ibi(
        vseq_ctx.cfg.ibi_target_addr,
        vseq_ctx.cfg.ibi_controller_dat_index,
        this);
      wait_bus_idle("wait for idle bus before Controller IBI queue-clear run");
      hci_helper.wait_bus_available(this);
      wait_irq(1'b0, "verify Controller IBI IRQ initially low");
      hci_helper.enable_broadcast_header(this);

      target_seq = smc_i3c_target_send_ibi_seq::type_id::create("target_seq");
      configure_target_ibi(target_seq);
      target_transfer_done = 1'b0;
      target_armed_event = uvm_event_pool::get_global(
        SMC_I3C_TARGET_IBI_ARMED_EVENT);
      target_armed_event.reset();
      fork : target_ibi_driver
        begin
          target_seq.start(vseq_ctx.i3c_sqr);
          target_transfer_done = 1'b1;
        end
      join_none

      target_armed_event.wait_on();
      vseq_ctx.cfg.ibi_bus_state = 2'd1;
      hci_helper.issue_dat_private_write(
        vseq_ctx.cfg.ibi_controller_dat_index, 8'hc3, 4'h1, this);

      fork : target_ibi_timeout_guard
        begin
          wait (target_transfer_done);
        end
        begin
          repeat (vseq_ctx.cfg.ibi_timeout_cycles)
            @(posedge vseq_ctx.cfg.vif.clk);
        end
      join_any
      disable target_ibi_timeout_guard;
      disable target_ibi_driver;
      if (!target_transfer_done)
        `uvm_fatal("IBI_QUEUE_CLEAR_BUS",
                   "Target-initiated IBI did not complete, so no record could be queued")
      if (!target_seq.observed_ack) begin
        // Precondition, not a queue-reset failure. Reported under its own ID so
        // triage separates "no record was ever produced" from "the reset did
        // not clear the queue". The run still FAILs.
        `uvm_error("IBI_QUEUE_CLEAR_BLOCKED_ACK_DEFECT",
                   "DUT Controller NACKed the target IBI address, so the HCI IBI queue was never filled")
        return;
      end

      // ---------------------------------------------------------------
      // Stage 2: confirm the queue is non-empty BEFORE the reset.
      // ---------------------------------------------------------------
      // Deliberately no read_ibi_record() here: PIOControl.IBI_PORT is a
      // destructive pop (smc_i3c_controller_hci_helper.sv:339) and draining the
      // record would leave the reset with nothing to clear.
      wait_irq(1'b1, "wait for Controller HCI IBI IRQ before queue reset");
      hci_helper.read_ibi_status(status_before, this);
      if (!status_before[2]) begin
        `uvm_error("IBI_QUEUE_CLEAR_NO_RECORD",
                   $sformatf("IBI_STATUS_THLD_STAT is low while IRQ is asserted, so the queue is not known to hold a record: status=0x%08h",
                             status_before))
        return;
      end

      // ---------------------------------------------------------------
      // Stage 3: reset the queue and check the FIFO-scoped properties.
      // ---------------------------------------------------------------
      `uvm_info("IBI_QUEUE_CLEAR",
                $sformatf("%s: queue holds a record (status=0x%08h), asserting IBI_QUEUE_RST",
                          scenario_name(), status_before),
                UVM_LOW)
      clear_ibi_queue(ral, self_cleared);

      hci_helper.read_ibi_status(status_after, this);
      if (status_after[2])
        `uvm_error("IBI_QUEUE_CLEAR_THLD_STAT",
                   $sformatf("IBI_STATUS_THLD_STAT remained set after IBI_QUEUE_RST: status=0x%08h",
                             status_after))

      // The IRQ is the same queue-derived condition seen at the pin, so it is
      // in scope for this reset. Sampled across a window rather than at one
      // instant, and non-fatal so the run reports every property it violated.
      begin
        int unsigned window_cycles;
        bit irq_low;

        window_cycles = vseq_ctx.cfg.ibi_timeout_cycles / 4;
        if (window_cycles == 0)
          window_cycles = 1;
        irq_low = 1'b0;
        for (int unsigned cycle = 0; cycle < window_cycles; cycle++) begin
          if (vseq_ctx.cfg.vif.i3c_irq === 1'b0) begin
            irq_low = 1'b1;
            break;
          end
          @(posedge vseq_ctx.cfg.vif.clk);
        end
        if (!irq_low)
          `uvm_error("IBI_QUEUE_CLEAR_IRQ",
                     $sformatf("i3c_irq stayed asserted for %0d cycles after IBI_QUEUE_RST emptied the queue",
                               window_cycles))
      end

      `uvm_info("IBI_QUEUE_CLEAR",
                $sformatf("%s: target=0x%02h status_before=0x%08h status_after=0x%08h self_cleared=%0b",
                          scenario_name(),
                          vseq_ctx.cfg.ibi_target_addr,
                          status_before, status_after, self_cleared),
                UVM_LOW)
    end
`else
    `uvm_fatal("IBI_QUEUE_CLEAR_RAL_BUILD",
               "Controller IBI queue-clear test requires SMC_USE_I3C_RAL")
`endif
`else
    `uvm_fatal("IBI_QUEUE_CLEAR_RTL_BUILD",
               "Controller IBI queue-clear test requires SMC_USE_I3C_RTL")
`endif
  endtask
endclass : smc_i3c_ibi_controller_rx_reset_flush_vseq

`endif // SMC_I3C_IBI_CONTROLLER_RX_RESET_FLUSH_VSEQ_SV
