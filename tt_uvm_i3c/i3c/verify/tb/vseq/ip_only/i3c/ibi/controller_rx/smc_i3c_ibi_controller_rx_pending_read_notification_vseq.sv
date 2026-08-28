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
// File        : smc_i3c_ibi_controller_rx_pending_read_notification_vseq.sv
// Description : Controller-RX Pending Read Notification virtual sequence.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-05
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_CONTROLLER_RX_PENDING_READ_NOTIFICATION_VSEQ_SV
`define SMC_I3C_IBI_CONTROLLER_RX_PENDING_READ_NOTIFICATION_VSEQ_SV

class smc_i3c_ibi_controller_rx_pending_read_notification_vseq extends
    smc_i3c_ibi_controller_mdb_base_vseq;
  `uvm_object_utils(smc_i3c_ibi_controller_rx_pending_read_notification_vseq)

  localparam bit [7:0] PENDING_READ_MDB = 8'hb0;
  localparam bit [7:0] AUTOCMD_GROUP_MASK = 8'he0;
  localparam bit [7:0] AUTOCMD_GROUP_VALUE = 8'ha0;
  localparam int unsigned FOLLOWUP_BYTE_COUNT = 4;

  function new(
      string name = "smc_i3c_ibi_controller_rx_pending_read_notification_vseq");
    super.new(name);
  endfunction

  virtual task body();
    super.body();
    if (!vseq_ctx.cfg.has_rtl)
      `uvm_fatal("IBI_PRN_MODE",
                 "Pending-read notification test requires DUT_MODE=rtl")
    if (vseq_ctx.cfg.ibi_dut_role != SMC_I3C_IBI_DUT_CONTROLLER)
      `uvm_fatal("IBI_PRN_ROLE",
                 "Pending-read notification test requires DUT-controller role")

`ifdef SMC_USE_I3C_RTL
`ifdef SMC_USE_I3C_RAL
    begin
      smc_i3c_controller_hci_helper #(TB_ADDR_WIDTH, TB_DATA_WIDTH)
        hci_helper;
      smc_i3c_target_send_ibi_seq target_ibi_seq;
      smc_i3c_target_private_read_seq target_read_seq;
      uvm_reg_data_t autocmd_capability;
      uvm_reg_data_t autocmd_data_rpt;
      byte unsigned expected_followup[$];
      byte unsigned expected_hci_payload[$];
      byte unsigned hci_data[$];
      bit [31:0] descriptor;
      bit [31:0] interrupt_status;
      bit ibi_done;
      bit followup_done;
      bit autocmd_supported;

      hci_helper = vseq_ctx.i3c_controller_hci_helper;
      if (hci_helper == null)
        `uvm_fatal("IBI_PRN_HELPER",
                   "Controller HCI helper is not available")

      // MIPI group 101 indicates Pending Read Notification. Match the group
      // bits in DAT so any registered group-101 MDB selects SDR0 Auto-Command.
      expected_followup.push_back(8'h11);
      expected_followup.push_back(8'h22);
      expected_followup.push_back(8'h33);
      expected_followup.push_back(8'h44);
      read_field(vseq_ctx.cfg.ral_model.I3CBase.HC_CAPABILITIES.AUTO_COMMAND,
                 autocmd_capability,
                 "read HCI Auto-Command capability");
      autocmd_supported = autocmd_capability[0];
      vseq_ctx.cfg.ibi_controller_autocmd_expected_data.delete();
      if (autocmd_supported) begin
        foreach (expected_followup[index]) begin
          vseq_ctx.cfg.ibi_controller_autocmd_expected_data.push_back(
            expected_followup[index]);
          expected_hci_payload.push_back(expected_followup[index]);
        end
        hci_helper.initialize_controller_ibi(
          vseq_ctx.cfg.ibi_target_addr,
          vseq_ctx.cfg.ibi_controller_dat_index, this,
          AUTOCMD_GROUP_MASK, AUTOCMD_GROUP_VALUE, 3'b000);
        read_field(vseq_ctx.cfg.ral_model.I3CBase.HC_CONTROL.AUTOCMD_DATA_RPT,
                   autocmd_data_rpt,
                   "read HCI Auto-Command reporting mode");
        if (autocmd_data_rpt[0] !== 1'b0)
          `uvm_fatal("IBI_PRN_REPORT_MODE",
                     "Pending-read test supports coalesced Auto-Command reporting only")
      end else begin
        // Auto-Command is optional. When HC_CAPABILITIES advertises zero, the
        // IBI remains a Regular IBI and host software must issue the required
        // follow-up Private Read after consuming the notification.
        hci_helper.initialize_controller_ibi(
          vseq_ctx.cfg.ibi_target_addr,
          vseq_ctx.cfg.ibi_controller_dat_index, this);
      end
      write_field(vseq_ctx.cfg.ral_model.I3CBase.HC_CONTROL.IBA_INCLUDE,
                  0, "disable broadcast header for PRN Private Read");

      wait_bus_idle("wait for idle bus before pending-read IBI");
      hci_helper.wait_bus_available(this);
      wait_irq(1'b0, "verify pending-read IRQ initially low");

      target_ibi_seq = smc_i3c_target_send_ibi_seq::type_id::create(
        "pending_read_ibi_seq");
      target_ibi_seq.target_addr = vseq_ctx.cfg.ibi_target_addr;
      target_ibi_seq.mdb_present = 1'b1;
      target_ibi_seq.mdb = PENDING_READ_MDB;
      target_ibi_seq.payload.delete();
      // The UVM Target initiates the IBI START after bus-available. This keeps
      // the IBI itself independent from the Controller command queue. With an
      // advertised Auto-Command capability the next transfer must be its
      // Private Read; otherwise software issues the Read after draining HCI.
      target_ibi_seq.start_on_idle = 1'b1;

      ibi_done = 1'b0;
      followup_done = 1'b0;
      vseq_ctx.cfg.ibi_controller_attempt_cases++;
      vseq_ctx.cfg.ibi_bus_state = 2'd0;
      vseq_ctx.cfg.vif.i3c_controller_expected_ack = 1'b1;
      if (autocmd_supported) begin
        target_read_seq = smc_i3c_target_private_read_seq::type_id::create(
          "pending_read_followup_seq");
        target_read_seq.target_addr = vseq_ctx.cfg.ibi_target_addr;
        foreach (expected_followup[index])
          target_read_seq.response_data.push_back(expected_followup[index]);
      end
      fork : pending_read_target_service
        begin
          target_ibi_seq.start(vseq_ctx.i3c_sqr);
          ibi_done = 1'b1;
          if (autocmd_supported) begin
            // The UVM Target keeps the announced data available and waits for
            // the Controller's SDR Private Read Auto-Command.
            target_read_seq.start(vseq_ctx.i3c_sqr);
            followup_done = target_read_seq.transfer_done;
          end
        end
      join_none

      wait_target_operation_done(ibi_done, "pending-read IBI");
      if (!target_ibi_seq.observed_ack)
        `uvm_fatal("IBI_PRN_NACK",
                   "DUT Controller NACKed the Pending Read Notification")

      if (autocmd_supported) begin
        // A supported and matching Auto-Command must lead to a Controller
        // Private Read. Keep this bounded for a directed diagnostic.
        if (!followup_done) begin
          repeat (vseq_ctx.cfg.ibi_timeout_cycles) begin
            @(posedge vseq_ctx.cfg.vif.clk);
            if (followup_done)
              break;
          end
        end
        if (!followup_done)
          `uvm_error("IBI_PRN_FOLLOWUP_TIMEOUT",
                     "Advertised Auto-Command did not issue a Private Read for group-101 MDB")
        else begin
          if (!target_read_seq.address_matched)
            `uvm_error("IBI_PRN_FOLLOWUP_ADDRESS",
                       $sformatf("expected Private Read DA=0x%02h/RnW=1, observed DA=0x%02h/RnW=%0b",
                                 vseq_ctx.cfg.ibi_target_addr,
                                 target_read_seq.observed_addr,
                                 target_read_seq.observed_dir))
          if (target_read_seq.response_data.size() != FOLLOWUP_BYTE_COUNT)
            `uvm_error("IBI_PRN_FOLLOWUP_LENGTH",
                       $sformatf("expected %0d follow-up bytes, target sent %0d",
                                 FOLLOWUP_BYTE_COUNT,
                                 target_read_seq.response_data.size()))
        end
      end

      // Auto-Command coalesces MDB/read bytes into an AutoCmd IBI record. If
      // the capability is absent, this is a Regular IBI containing only MDB.
      wait_irq(1'b1, "wait for pending-read HCI IBI IRQ");
      hci_helper.read_ibi_status(interrupt_status, this);
      if (!interrupt_status[2])
        `uvm_error("IBI_PRN_IRQ_STATUS",
                   $sformatf("IRQ asserted without IBI threshold status: 0x%08h",
                             interrupt_status))
      hci_helper.read_ibi_record(descriptor, hci_data, this);
      check_hci_record("pending-read notification", PENDING_READ_MDB,
                       expected_hci_payload,
                       autocmd_supported ? 3'b100 : 3'b000,
                       descriptor, hci_data);
      wait_scoreboard_completion(
        1, "wait for pending-read Controller scoreboard correlation");
      wait_irq(1'b0, "wait for pending-read IRQ clear after FIFO drain");
      hci_helper.read_ibi_status(interrupt_status, this);
      if (interrupt_status[2])
        `uvm_error("IBI_PRN_IRQ_CLEAR",
                   $sformatf("IBI threshold status remained set after drain: 0x%08h",
                           interrupt_status))

      if (!autocmd_supported)
        run_software_pending_read(4'he, expected_followup, hci_helper,
                                  "pending-read software follow-up");

      if ((vseq_ctx.cfg.ibi_controller_expected_events != 1) ||
          (vseq_ctx.cfg.ibi_controller_actual_events != 1))
        `uvm_fatal("IBI_PRN_EVENT_COUNT",
                   $sformatf("expected/actual Controller events must be 1/1, got %0d/%0d",
                             vseq_ctx.cfg.ibi_controller_expected_events,
                             vseq_ctx.cfg.ibi_controller_actual_events))
      if (vseq_ctx.cfg.ibi_sb_mismatch_count != 0)
        `uvm_error("IBI_PRN_SCOREBOARD",
                   $sformatf("Pending-read scoreboard mismatches=%0d",
                             vseq_ctx.cfg.ibi_sb_mismatch_count))
      if (vseq_ctx.cfg.ibi_cov_completion_samples == 0)
        `uvm_fatal("IBI_PRN_COVERAGE",
                   "Pending-read completion was not sampled by coverage")

      disable pending_read_target_service;
      `uvm_info("IBI_PENDING_READ",
                $sformatf("Completed group-101 MDB check: autocmd_supported=%0b follow-up=%0b descriptor=0x%08h data=%0d IRQ events=%0d",
                          autocmd_supported, followup_done, descriptor,
                          hci_data.size(),
                          vseq_ctx.cfg.ibi_controller_irq_events),
                UVM_LOW)
    end
`else
    `uvm_fatal("IBI_PRN_RAL_BUILD",
               "Pending-read test requires SMC_USE_I3C_RAL")
`endif
`else
    `uvm_fatal("IBI_PRN_RTL_BUILD",
               "Pending-read test requires SMC_USE_I3C_RTL")
`endif
  endtask
endclass : smc_i3c_ibi_controller_rx_pending_read_notification_vseq

`endif // SMC_I3C_IBI_CONTROLLER_RX_PENDING_READ_NOTIFICATION_VSEQ_SV
