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
// File        : smc_i3c_ibi_controller_rx_basic_vseq.sv
// Description : Virtual sequence for I3C IBI controller receive.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-06
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_CONTROLLER_RX_BASIC_VSEQ_SV
`define SMC_I3C_IBI_CONTROLLER_RX_BASIC_VSEQ_SV

class smc_i3c_ibi_controller_rx_basic_vseq extends smc_i3c_ibi_base_vseq;
  `uvm_object_utils(smc_i3c_ibi_controller_rx_basic_vseq)

  // === Idle-bus IBI NACK bug repro (source-level; no plusarg) ==============
  //   0 (default) : normal workaround. The Target IBI rides a Controller-opened
  //                 address window (start_on_idle=0); the DUT ACKs; test passes.
  //   1           : attempt the idle-bus NACK repro (analysis doc
  //                 doc/i3c_controller_ibi_idle_nack_analysis.md, section 7). The
  //                 Target drives the IBI START autonomously on an idle bus with
  //                 no host command. FINDING (git bf9d53b run): with the standard
  //                 HCI setup here, initialize_controller_ibi preloads a valid
  //                 matching DAT entry, so dat_rdata is NOT stale at the 9th bit
  //                 -> ibi_abort=0 -> the DUT ACKs and the test still passes; the
  //                 idle-NACK does NOT reproduce on this path. The idle-NACK is a
  //                 reset/cold-state corner (dat_rdata=0 before any DAT read),
  //                 established by construction in the RTL bug report rather than
  //                 via this test. The Device driver only raises the armed event
  //                 when start_on_idle=0 (smc_i3c_target_driver.sv:90), so this
  //                 mode also skips the arm wait and the private-write window.
  // Keep 1'b0 (workaround path) for regression.
  localparam bit REPRO_IDLE_NACK = 1'b0;

  function new(string name = "smc_i3c_ibi_controller_rx_basic_vseq");
    super.new(name);
  endfunction

  protected virtual function void configure_target_ibi(
      smc_i3c_target_send_ibi_seq target_seq);
    target_seq.target_addr = vseq_ctx.cfg.ibi_target_addr;
    target_seq.mdb_present = 1'b1;
    target_seq.mdb = vseq_ctx.cfg.ibi_basic_mdb;
    target_seq.payload.delete();
    target_seq.start_on_idle = REPRO_IDLE_NACK ? 1'b1 : 1'b0;
  endfunction

  protected virtual function string scenario_name();
    return "Controller MDB-only receive";
  endfunction

  virtual task body();
    super.body();
    if (!vseq_ctx.cfg.has_rtl)
      `uvm_fatal("IBI_CTRL_MODE",
                 "Controller receive test requires DUT_MODE=rtl")
    if (vseq_ctx.cfg.ibi_dut_role != SMC_I3C_IBI_DUT_CONTROLLER)
      `uvm_fatal("IBI_CTRL_ROLE",
                 "Controller receive vseq requires DUT-controller role")

`ifdef SMC_USE_I3C_RTL
`ifdef SMC_USE_I3C_RAL
    begin
      smc_i3c_target_send_ibi_seq target_seq;
      smc_i3c_controller_hci_helper #(TB_ADDR_WIDTH, TB_DATA_WIDTH)
        hci_helper;
      bit [31:0] interrupt_status;
      bit [31:0] descriptor;
      byte unsigned hci_data[$];
      bit target_transfer_done;
      uvm_event target_armed_event;
      int unsigned completion_before;
      int unsigned mismatch_before;
      int unsigned expected_before;
      int unsigned actual_before;
      int unsigned attempt_samples_before;
      int unsigned completion_samples_before;
      int unsigned queue_irq_samples_before;

      hci_helper = vseq_ctx.i3c_controller_hci_helper;
      if (hci_helper == null)
        `uvm_fatal("IBI_CTRL_HCI_HELPER",
                   "Controller HCI helper is not available")

      completion_before = vseq_ctx.cfg.ibi_sb_completion_count;
      mismatch_before = vseq_ctx.cfg.ibi_sb_mismatch_count;
      expected_before = vseq_ctx.cfg.ibi_controller_expected_events;
      actual_before = vseq_ctx.cfg.ibi_controller_actual_events;
      attempt_samples_before = vseq_ctx.cfg.ibi_cov_attempt_samples;
      completion_samples_before = vseq_ctx.cfg.ibi_cov_completion_samples;
      queue_irq_samples_before = vseq_ctx.cfg.ibi_cov_queue_irq_samples;

      hci_helper.initialize_controller_ibi(
        vseq_ctx.cfg.ibi_target_addr,
        vseq_ctx.cfg.ibi_controller_dat_index,
        this);
      wait_bus_idle("wait for idle bus before Controller-RX IBI");
      hci_helper.wait_bus_available(this);
      wait_irq(1'b0, "verify Controller IBI IRQ initially low");
      hci_helper.enable_broadcast_header(this);

      target_seq = smc_i3c_target_send_ibi_seq::type_id::create(
        "target_seq");
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

      if (!REPRO_IDLE_NACK) begin
        target_armed_event.wait_on();
        vseq_ctx.cfg.ibi_bus_state = 2'd1;
        // This command only opens the active-transfer IBI arbitration window.
        // The current Controller flow returns to Idle after the IBI, so the
        // Target sequence completes at the IBI STOP and does not await a resume.
        hci_helper.issue_dat_private_write(
          vseq_ctx.cfg.ibi_controller_dat_index,
          8'hc3, 4'h1, this);
      end
      // REPRO_IDLE_NACK: the Target drives the IBI START autonomously on the
      // idle bus; the driver does not arm (start_on_idle=1) and no host command
      // opens a window, so neither wait on the armed event nor issue a private
      // write. The DUT is expected to NACK, tripping IBI_CTRL_NACK below.

      fork : target_ibi_timeout_guard
        begin
          wait (target_transfer_done);
        end
        begin
          repeat (vseq_ctx.cfg.ibi_timeout_cycles)
            @(posedge vseq_ctx.cfg.vif.clk);
          if (!target_transfer_done)
            `uvm_fatal("IBI_CTRL_BUS_TIMEOUT",
                       "Timed out waiting for target-initiated IBI bus transfer")
        end
      join_any
      disable target_ibi_timeout_guard;
      disable target_ibi_driver;
      if (!target_transfer_done)
        `uvm_fatal("IBI_CTRL_BUS",
                   "Target-initiated IBI did not complete")
      if (!target_seq.observed_ack)
        `uvm_fatal("IBI_CTRL_NACK",
                   "DUT Controller NACKed the target IBI address")

      wait_irq(1'b1, "wait for Controller HCI IBI IRQ");
      hci_helper.read_ibi_status(interrupt_status, this);
      if (!interrupt_status[2])
        `uvm_fatal("IBI_CTRL_IRQ_STATUS",
                   $sformatf("IBI_STATUS_THLD_STAT is low while IRQ is asserted: status=0x%08h",
                             interrupt_status))

      hci_helper.read_ibi_record(descriptor, hci_data, this);
      wait_scoreboard_completion(
        completion_before + 1,
        "wait for Controller IBI scoreboard completion");
      wait_irq(1'b0, "wait for Controller IBI IRQ clear after FIFO drain");
      hci_helper.read_ibi_status(interrupt_status, this);
      if (interrupt_status[2])
        `uvm_fatal("IBI_CTRL_IRQ_CLEAR",
                   $sformatf("IBI_STATUS_THLD_STAT remained set after FIFO drain: status=0x%08h",
                             interrupt_status))

      // Report scoreboard field mismatches as an error instead of aborting the
      // sim: the run continues through the event-count and coverage gates below
      // so the full end-of-test picture is visible.
      if (vseq_ctx.cfg.ibi_sb_mismatch_count != mismatch_before)
        `uvm_error("IBI_CTRL_SB",
                   $sformatf("Controller IBI added scoreboard mismatches=%0d",
                             vseq_ctx.cfg.ibi_sb_mismatch_count -
                             mismatch_before))
      if (((vseq_ctx.cfg.ibi_controller_expected_events - expected_before) != 1) ||
          ((vseq_ctx.cfg.ibi_controller_actual_events - actual_before) != 1))
        `uvm_fatal("IBI_CTRL_EVENT_COUNT",
                   $sformatf("This scenario must add one expected/actual Controller event, got %0d/%0d",
                             vseq_ctx.cfg.ibi_controller_expected_events -
                             expected_before,
                             vseq_ctx.cfg.ibi_controller_actual_events -
                             actual_before))
      if ((vseq_ctx.cfg.ibi_cov_attempt_samples - attempt_samples_before == 0) ||
          (vseq_ctx.cfg.ibi_cov_completion_samples - completion_samples_before == 0) ||
          (vseq_ctx.cfg.ibi_cov_queue_irq_samples - queue_irq_samples_before == 0))
        `uvm_fatal("IBI_CTRL_COVERAGE",
                   $sformatf("This scenario added incomplete Controller coverage attempt=%0d completion=%0d queue_irq=%0d",
                             vseq_ctx.cfg.ibi_cov_attempt_samples -
                             attempt_samples_before,
                             vseq_ctx.cfg.ibi_cov_completion_samples -
                             completion_samples_before,
                             vseq_ctx.cfg.ibi_cov_queue_irq_samples -
                             queue_irq_samples_before))

      `uvm_info("IBI_CTRL_RECEIVE",
                $sformatf("%s: target=0x%02h MDB=0x%02h payload=%0d descriptor=0x%08h IRQ events=%0d",
                          scenario_name(),
                          vseq_ctx.cfg.ibi_target_addr,
                          target_seq.mdb,
                          target_seq.payload.size(),
                          descriptor,
                          vseq_ctx.cfg.ibi_controller_irq_events),
                UVM_LOW)
    end
`else
    `uvm_fatal("IBI_CTRL_RAL_BUILD",
               "Controller receive test requires SMC_USE_I3C_RAL")
`endif
`else
    `uvm_fatal("IBI_CTRL_RTL_BUILD",
               "Controller receive test requires SMC_USE_I3C_RTL")
`endif
  endtask
endclass : smc_i3c_ibi_controller_rx_basic_vseq

`endif // SMC_I3C_IBI_CONTROLLER_RX_BASIC_VSEQ_SV
