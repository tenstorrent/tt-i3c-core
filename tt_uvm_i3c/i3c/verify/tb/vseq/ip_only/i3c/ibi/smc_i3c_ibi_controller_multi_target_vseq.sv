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
// File        : smc_i3c_ibi_controller_multi_target_vseq.sv
// Description : Virtual sequence for multi-target Controller IBI arbitration.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-25
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_CONTROLLER_MULTI_TARGET_VSEQ_SV
`define SMC_I3C_IBI_CONTROLLER_MULTI_TARGET_VSEQ_SV

class smc_i3c_ibi_controller_multi_target_vseq extends smc_i3c_ibi_base_vseq;
  `uvm_object_utils(smc_i3c_ibi_controller_multi_target_vseq)

  localparam int unsigned PRIMARY_DAT_INDEX = 0;
  localparam int unsigned SECONDARY_DAT_INDEX = 1;

  function new(string name = "smc_i3c_ibi_controller_multi_target_vseq");
    super.new(name);
  endfunction

`ifdef SMC_USE_I3C_RTL
`ifdef SMC_USE_I3C_RAL
  protected task wait_two_targets(ref bit primary_done,
                                  ref bit secondary_done);
    if (primary_done && secondary_done)
      return;

    repeat (vseq_ctx.cfg.ibi_timeout_cycles) begin
      @(posedge vseq_ctx.cfg.vif.clk);
      if (primary_done && secondary_done)
        return;
    end

    `uvm_fatal("IBI_CTRL_MULTI_TIMEOUT",
               "Timed out waiting for concurrent Target arbitration")
  endtask

  protected task wait_one_target(ref bit target_done,
                                 input string operation);
    if (target_done)
      return;

    repeat (vseq_ctx.cfg.ibi_timeout_cycles) begin
      @(posedge vseq_ctx.cfg.vif.clk);
      if (target_done)
        return;
    end

    `uvm_fatal("IBI_CTRL_MULTI_TIMEOUT",
               $sformatf("%s timed out", operation))
  endtask

  protected function bit [6:0] decode_record_addr(
      bit [31:0] descriptor,
      bit [6:0] primary_addr,
      bit [6:0] secondary_addr);
    bit [7:0] ibi_id;

    ibi_id = descriptor[15:8];
    if ((ibi_id == {1'b0, primary_addr}) ||
        (ibi_id == {primary_addr, 1'b1}))
      return primary_addr;
    if ((ibi_id == {1'b0, secondary_addr}) ||
        (ibi_id == {secondary_addr, 1'b1}))
      return secondary_addr;
    `uvm_fatal("IBI_CTRL_MULTI_ID",
               $sformatf("IBI_ID 0x%02h matches neither DAT address 0x%02h/0x%02h",
                         ibi_id, primary_addr, secondary_addr))
    return '0;
  endfunction

  protected task check_record(
      input bit [31:0] descriptor,
      input byte unsigned data[$],
      input bit [6:0] expected_addr,
      input bit [7:0] expected_mdb,
      input bit [6:0] primary_addr,
      input bit [6:0] secondary_addr,
      input string operation);
    bit [6:0] actual_addr;

    actual_addr = decode_record_addr(
      descriptor, primary_addr, secondary_addr);
    if (actual_addr != expected_addr)
      `uvm_fatal("IBI_CTRL_MULTI_ORDER",
                 $sformatf("%s expected address 0x%02h, got 0x%02h",
                           operation, expected_addr, actual_addr))
    if (descriptor[31:30] != 2'b00)
      `uvm_fatal("IBI_CTRL_MULTI_STATUS",
                 $sformatf("%s returned failed descriptor 0x%08h",
                           operation, descriptor))
    if ((descriptor[7:0] != 1) || (data.size() != 1)) begin
      `uvm_fatal("IBI_CTRL_MULTI_DATA",
                 $sformatf("%s expected MDB 0x%02h only, descriptor=0x%08h bytes=%0d",
                           operation, expected_mdb, descriptor, data.size()))
    end
    else if (data[0] != expected_mdb) begin
      `uvm_fatal("IBI_CTRL_MULTI_MDB",
                 $sformatf("%s expected MDB 0x%02h, got 0x%02h",
                           operation, expected_mdb, data[0]))
    end
  endtask
`endif
`endif

  virtual task body();
    super.body();
    if (!vseq_ctx.cfg.has_rtl)
      `uvm_fatal("IBI_CTRL_MULTI_MODE",
                 "Controller multi-target test requires DUT_MODE=rtl")
    if (vseq_ctx.cfg.ibi_dut_role != SMC_I3C_IBI_DUT_CONTROLLER)
      `uvm_fatal("IBI_CTRL_MULTI_ROLE",
                 "Controller multi-target vseq requires DUT-controller role")

`ifdef SMC_USE_I3C_RTL
`ifdef SMC_USE_I3C_RAL
    begin
      smc_i3c_controller_hci_helper #(TB_ADDR_WIDTH, TB_DATA_WIDTH)
        hci_helper;
      smc_i3c_target_send_ibi_seq primary_seq;
      smc_i3c_target_send_ibi_seq secondary_seq;
      smc_i3c_target_send_ibi_seq retry_seq;
      i3c_sequencer loser_sqr;
      uvm_event primary_armed;
      uvm_event secondary_armed;
      uvm_event retry_armed;
      bit primary_done;
      bit secondary_done;
      bit retry_done;
      bit [6:0] primary_addr;
      bit [6:0] secondary_addr;
      bit [6:0] winner_addr;
      bit [6:0] loser_addr;
      bit [7:0] winner_mdb;
      bit [7:0] loser_mdb;
      int unsigned winner_dat_index;
      int unsigned loser_dat_index;
      bit [31:0] interrupt_status;
      bit [31:0] descriptor;
      byte unsigned hci_data[$];

      if ((vseq_ctx.i3c_sqr == null) ||
          (vseq_ctx.i3c_secondary_sqr == null))
        `uvm_fatal("IBI_CTRL_MULTI_SQR",
                   "Both Target sequencers are required")
      hci_helper = vseq_ctx.i3c_controller_hci_helper;
      if (hci_helper == null)
        `uvm_fatal("IBI_CTRL_MULTI_HELPER",
                   "Controller HCI helper is not available")

      primary_addr = vseq_ctx.cfg.ibi_target_addr;
      secondary_addr = vseq_ctx.cfg.ibi_secondary_target_addr;
      winner_addr = (primary_addr < secondary_addr) ?
        primary_addr : secondary_addr;
      loser_addr = (primary_addr < secondary_addr) ?
        secondary_addr : primary_addr;
      winner_dat_index = (winner_addr == primary_addr) ?
        PRIMARY_DAT_INDEX : SECONDARY_DAT_INDEX;
      loser_dat_index = (loser_addr == primary_addr) ?
        PRIMARY_DAT_INDEX : SECONDARY_DAT_INDEX;
      loser_sqr = (loser_addr == primary_addr) ?
        vseq_ctx.i3c_sqr : vseq_ctx.i3c_secondary_sqr;
      winner_mdb = (winner_addr == primary_addr) ?
        vseq_ctx.cfg.ibi_basic_mdb : (vseq_ctx.cfg.ibi_basic_mdb ^ 8'h3c);
      loser_mdb = (loser_addr == primary_addr) ?
        vseq_ctx.cfg.ibi_basic_mdb : (vseq_ctx.cfg.ibi_basic_mdb ^ 8'h3c);

      hci_helper.initialize_controller_ibi(
        primary_addr, PRIMARY_DAT_INDEX, this);
      hci_helper.program_dat_entry(
        SECONDARY_DAT_INDEX, secondary_addr, '0, 1'b0, 1'b1, this);
      wait_bus_idle("wait for idle bus before multi-target IBI");
      hci_helper.wait_bus_available(this);
      wait_irq(1'b0, "verify multi-target IBI IRQ initially low");
      hci_helper.enable_broadcast_header(this);

      primary_seq = smc_i3c_target_send_ibi_seq::type_id::create(
        "primary_seq");
      primary_seq.target_addr = primary_addr;
      primary_seq.mdb = vseq_ctx.cfg.ibi_basic_mdb;
      primary_seq.start_on_idle = 1'b0;
      secondary_seq = smc_i3c_target_send_ibi_seq::type_id::create(
        "secondary_seq");
      secondary_seq.target_addr = secondary_addr;
      secondary_seq.mdb = vseq_ctx.cfg.ibi_basic_mdb ^ 8'h3c;
      secondary_seq.start_on_idle = 1'b0;

      primary_armed = uvm_event_pool::get_global(
        $sformatf("%s_0", SMC_I3C_TARGET_IBI_SLOT_ARMED_EVENT));
      secondary_armed = uvm_event_pool::get_global(
        $sformatf("%s_1", SMC_I3C_TARGET_IBI_SLOT_ARMED_EVENT));
      primary_armed.reset();
      secondary_armed.reset();
      primary_done = 1'b0;
      secondary_done = 1'b0;
      fork : concurrent_targets
        begin
          primary_seq.start(vseq_ctx.i3c_sqr);
          primary_done = 1'b1;
        end
        begin
          secondary_seq.start(vseq_ctx.i3c_secondary_sqr);
          secondary_done = 1'b1;
        end
      join_none

      primary_armed.wait_on();
      secondary_armed.wait_on();
      vseq_ctx.cfg.ibi_requester_count = 2;
      vseq_ctx.cfg.ibi_arb_outcome = 2'd1;
      vseq_ctx.cfg.ibi_bus_state = 2'd1;
      vseq_ctx.cfg.vif.i3c_controller_expected_addr = winner_addr;
      hci_helper.issue_dat_private_write(
        winner_dat_index, 8'hc3, 4'h1, this);
      wait_two_targets(primary_done, secondary_done);
      disable concurrent_targets;

      if ((primary_seq.observed_ack + secondary_seq.observed_ack) != 1)
        `uvm_fatal("IBI_CTRL_MULTI_WINNER",
                   $sformatf("Expected one ACK, primary=%0b secondary=%0b",
                             primary_seq.observed_ack,
                             secondary_seq.observed_ack))
      if (((winner_addr == primary_addr) && !primary_seq.observed_ack) ||
          ((winner_addr == secondary_addr) && !secondary_seq.observed_ack))
        `uvm_fatal("IBI_CTRL_MULTI_ARBITRATION",
                   $sformatf("Lowest address 0x%02h did not win arbitration",
                             winner_addr))
      if ((vseq_ctx.cfg.ibi_controller_arbitration_losses != 1) ||
          (vseq_ctx.cfg.ibi_controller_loser_release_checks != 1) ||
          (vseq_ctx.cfg.ibi_controller_loser_release_failures != 0))
        `uvm_fatal("IBI_CTRL_MULTI_RELEASE",
                   $sformatf("Loser release evidence losses=%0d checks=%0d failures=%0d",
                             vseq_ctx.cfg.ibi_controller_arbitration_losses,
                             vseq_ctx.cfg.ibi_controller_loser_release_checks,
                             vseq_ctx.cfg.ibi_controller_loser_release_failures))

      wait_irq(1'b1, "wait for winner HCI IBI IRQ");
      hci_helper.read_ibi_status(interrupt_status, this);
      if (!interrupt_status[2])
        `uvm_fatal("IBI_CTRL_MULTI_IRQ",
                   "Winner did not set IBI_STATUS_THLD_STAT")
      hci_helper.read_ibi_record(descriptor, hci_data, this);
      check_record(descriptor, hci_data, winner_addr, winner_mdb,
                   primary_addr, secondary_addr, "winner HCI record");
      wait_scoreboard_completion(1, "wait for winner scoreboard completion");
      wait_irq(1'b0, "wait for winner IRQ clear");

      wait_bus_idle("wait for idle bus before loser retry");
      hci_helper.wait_bus_available(this);
      retry_seq = smc_i3c_target_send_ibi_seq::type_id::create("retry_seq");
      retry_seq.target_addr = loser_addr;
      retry_seq.mdb = loser_mdb;
      retry_seq.start_on_idle = 1'b0;
      retry_armed = uvm_event_pool::get_global(
        $sformatf("%s_%0d", SMC_I3C_TARGET_IBI_SLOT_ARMED_EVENT,
                  (loser_addr == primary_addr) ? 0 : 1));
      retry_armed.reset();
      retry_done = 1'b0;
      fork : loser_retry
        begin
          retry_seq.start(loser_sqr);
          retry_done = 1'b1;
        end
      join_none
      retry_armed.wait_on();
      vseq_ctx.cfg.ibi_requester_count = 1;
      vseq_ctx.cfg.ibi_arb_outcome = 2'd0;
      vseq_ctx.cfg.vif.i3c_controller_expected_addr = loser_addr;
      hci_helper.issue_dat_private_write(
        loser_dat_index, 8'h5a, 4'h2, this);
      wait_one_target(retry_done, "loser retry");
      disable loser_retry;
      if (!retry_seq.observed_ack)
        `uvm_fatal("IBI_CTRL_MULTI_RETRY",
                   $sformatf("Controller did not service loser 0x%02h",
                             loser_addr))

      wait_irq(1'b1, "wait for loser HCI IBI IRQ");
      hci_helper.read_ibi_record(descriptor, hci_data, this);
      check_record(descriptor, hci_data, loser_addr, loser_mdb,
                   primary_addr, secondary_addr, "loser HCI record");
      wait_scoreboard_completion(2, "wait for loser scoreboard completion");
      wait_irq(1'b0, "wait for loser IRQ clear");

      if ((vseq_ctx.cfg.ibi_controller_expected_events != 2) ||
          (vseq_ctx.cfg.ibi_controller_actual_events != 2))
        `uvm_fatal("IBI_CTRL_MULTI_EVENT_COUNT",
                   $sformatf("Expected/actual Controller events must be 2/2, got %0d/%0d",
                             vseq_ctx.cfg.ibi_controller_expected_events,
                             vseq_ctx.cfg.ibi_controller_actual_events))
      if (vseq_ctx.cfg.ibi_sb_mismatch_count != 0)
        `uvm_error("IBI_CTRL_MULTI_SB",
                   $sformatf("Controller multi-target scoreboard mismatches=%0d",
                             vseq_ctx.cfg.ibi_sb_mismatch_count))

      `uvm_info("IBI_CTRL_MULTI_TARGET",
                $sformatf("Concurrent arbitration winner=0x%02h; loser=0x%02h released SDA and was serviced later",
                          winner_addr, loser_addr),
                UVM_LOW)
    end
`else
    `uvm_fatal("IBI_CTRL_MULTI_RAL_BUILD",
               "Controller multi-target test requires SMC_USE_I3C_RAL")
`endif
`else
    `uvm_fatal("IBI_CTRL_MULTI_RTL_BUILD",
               "Controller multi-target test requires SMC_USE_I3C_RTL")
`endif
  endtask
endclass : smc_i3c_ibi_controller_multi_target_vseq

`endif // SMC_I3C_IBI_CONTROLLER_MULTI_TARGET_VSEQ_SV
