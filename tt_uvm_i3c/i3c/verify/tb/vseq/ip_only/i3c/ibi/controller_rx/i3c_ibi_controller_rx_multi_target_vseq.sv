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
// File        : i3c_ibi_controller_rx_multi_target_vseq.sv
// Description : Four-Target Controller IBI arbitration virtual sequence.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-12
//
// *****************************************************************************

`ifndef I3C_IBI_CONTROLLER_RX_MULTI_TARGET_VSEQ_SV
`define I3C_IBI_CONTROLLER_RX_MULTI_TARGET_VSEQ_SV

class i3c_ibi_controller_rx_multi_target_vseq extends i3c_ibi_base_vseq;
  `uvm_object_utils(i3c_ibi_controller_rx_multi_target_vseq)

  localparam int unsigned TARGET_COUNT = 4;

  function new(string name = "i3c_ibi_controller_rx_multi_target_vseq");
    super.new(name);
  endfunction

`ifdef I3C_DV_NATIVE_RTL
`ifdef I3C_DV_NATIVE_RAL
  protected task wait_four_targets(ref bit done_0,
                                   ref bit done_1,
                                   ref bit done_2,
                                   ref bit done_3);
    virtual i3c_if primary_target_vif;

    if (done_0 && done_1 && done_2 && done_3)
      return;
    repeat (vseq_ctx.cfg.ibi_timeout_cycles) begin
      @(posedge vseq_ctx.cfg.vif.clk);
      if (done_0 && done_1 && done_2 && done_3)
        return;
    end
    primary_target_vif = i3c_vif_for_slot(0);
    `uvm_fatal("IBI_CTRL_MULTI_TIMEOUT",
               $sformatf("Concurrent arbitration timed out: done=%0b/%0b/%0b/%0b armed=%0b/%0b/%0b/%0b start_seen=%0b/%0b/%0b/%0b driver_completed=%0b/%0b/%0b/%0b bus_scl=%b bus_sda=%b",
                         done_0, done_1, done_2, done_3,
                         vseq_ctx.cfg.ibi_target_driver_armed[0],
                         vseq_ctx.cfg.ibi_target_driver_armed[1],
                         vseq_ctx.cfg.ibi_target_driver_armed[2],
                         vseq_ctx.cfg.ibi_target_driver_armed[3],
                         vseq_ctx.cfg.ibi_target_driver_start_seen[0],
                         vseq_ctx.cfg.ibi_target_driver_start_seen[1],
                         vseq_ctx.cfg.ibi_target_driver_start_seen[2],
                         vseq_ctx.cfg.ibi_target_driver_start_seen[3],
                         vseq_ctx.cfg.ibi_target_driver_completed[0],
                         vseq_ctx.cfg.ibi_target_driver_completed[1],
                         vseq_ctx.cfg.ibi_target_driver_completed[2],
                         vseq_ctx.cfg.ibi_target_driver_completed[3],
                         primary_target_vif.scl_i,
                         primary_target_vif.sda_i))
  endtask

  protected task wait_four_targets_ready();
    virtual i3c_if target_vif_0;
    virtual i3c_if target_vif_1;
    virtual i3c_if target_vif_2;
    virtual i3c_if target_vif_3;

    target_vif_0 = i3c_vif_for_slot(0);
    target_vif_1 = i3c_vif_for_slot(1);
    target_vif_2 = i3c_vif_for_slot(2);
    target_vif_3 = i3c_vif_for_slot(3);
    repeat (vseq_ctx.cfg.ibi_timeout_cycles) begin
      if (target_vif_0.device_driver_wait_for_start_active &&
          target_vif_1.device_driver_wait_for_start_active &&
          target_vif_2.device_driver_wait_for_start_active &&
          target_vif_3.device_driver_wait_for_start_active)
        return;
      @(posedge vseq_ctx.cfg.vif.clk);
    end
    `uvm_fatal("IBI_CTRL_MULTI_READY",
               $sformatf("Targets did not become START-ready: armed=%0b/%0b/%0b/%0b ready=%0b/%0b/%0b/%0b",
                         vseq_ctx.cfg.ibi_target_driver_armed[0],
                         vseq_ctx.cfg.ibi_target_driver_armed[1],
                         vseq_ctx.cfg.ibi_target_driver_armed[2],
                         vseq_ctx.cfg.ibi_target_driver_armed[3],
                         target_vif_0.device_driver_wait_for_start_active,
                         target_vif_1.device_driver_wait_for_start_active,
                         target_vif_2.device_driver_wait_for_start_active,
                         target_vif_3.device_driver_wait_for_start_active))
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

  protected function int unsigned slot_for_addr(
      input bit [6:0] address);
    for (int unsigned slot = 0; slot < TARGET_COUNT; slot++) begin
      if (vseq_ctx.cfg.ibi_target_addr_by_slot[slot] == address)
        return slot;
    end
    `uvm_fatal("IBI_CTRL_MULTI_ADDR",
               $sformatf("Address 0x%02h has no active Target slot", address))
    return 0;
  endfunction

  protected function bit [6:0] decode_record_addr(bit [31:0] descriptor);
    bit [7:0] ibi_id;

    ibi_id = descriptor[15:8];
    for (int unsigned slot = 0; slot < TARGET_COUNT; slot++) begin
      if (ibi_id == {vseq_ctx.cfg.ibi_target_addr_by_slot[slot], 1'b1})
        return vseq_ctx.cfg.ibi_target_addr_by_slot[slot];
    end
    `uvm_fatal("IBI_CTRL_MULTI_ID",
               $sformatf("IBI_ID 0x%02h matches no active DAT address", ibi_id))
    return '0;
  endfunction

  protected task check_record(input bit [31:0] descriptor,
                              input byte unsigned data[$],
                              input bit [6:0] expected_addr,
                              input bit [7:0] expected_mdb,
                              input string operation);
    bit [6:0] actual_addr;

    actual_addr = decode_record_addr(descriptor);
    if (actual_addr != expected_addr)
      `uvm_fatal("IBI_CTRL_MULTI_ORDER",
                 $sformatf("%s expected address 0x%02h, got 0x%02h",
                           operation, expected_addr, actual_addr))
    if (descriptor[31:30] != 2'b00)
      `uvm_fatal("IBI_CTRL_MULTI_STATUS",
                 $sformatf("%s returned failed descriptor 0x%08h",
                           operation, descriptor))
    if ((descriptor[7:0] != 1) || (data.size() != 1))
      `uvm_fatal("IBI_CTRL_MULTI_DATA",
                 $sformatf("%s expected MDB 0x%02h only, descriptor=0x%08h bytes=%0d first=0x%02h",
                           operation, expected_mdb, descriptor, data.size(),
                           (data.size() == 0) ? 8'h00 : data[0]))
    else if (data[0] != expected_mdb)
      `uvm_fatal("IBI_CTRL_MULTI_DATA",
                 $sformatf("%s expected MDB 0x%02h, got 0x%02h",
                           operation, expected_mdb, data[0]))
  endtask

  protected task service_target(
      input i3c_controller_hci_helper #(TB_ADDR_WIDTH, TB_DATA_WIDTH)
        hci_helper,
      input bit [6:0] target_addr,
      input bit [7:0] target_mdb,
      input int unsigned expected_completion);
    i3c_target_send_ibi_seq retry_seq;
    uvm_event armed_event;
    bit retry_done;
    bit [31:0] descriptor;
    byte unsigned hci_data[$];
    int unsigned slot;

    slot = slot_for_addr(target_addr);
    wait_bus_idle($sformatf("wait for idle bus before servicing slot %0d", slot));
    hci_helper.wait_bus_available(this);
    retry_seq = i3c_target_send_ibi_seq::type_id::create(
      $sformatf("retry_seq_%0d", slot));
    retry_seq.target_addr = target_addr;
    retry_seq.mdb = target_mdb;
    retry_seq.start_on_idle = 1'b0;
    armed_event = uvm_event_pool::get_global(
      $sformatf("%s_%0d", I3C_TARGET_IBI_SLOT_ARMED_EVENT, slot));
    armed_event.reset();
    retry_done = 1'b0;
    fork : target_retry
      begin
        retry_seq.start(vseq_ctx.i3c_target_sqr[slot]);
        retry_done = 1'b1;
      end
    join_none
    armed_event.wait_on();
    vseq_ctx.cfg.ibi_requester_count = 1;
    vseq_ctx.cfg.ibi_arb_outcome = 2'd0;
    vseq_ctx.cfg.vif.i3c_controller_expected_addr = target_addr;
    hci_helper.issue_dat_private_write(slot, 8'h5a, 4'h2, this);
    wait_one_target(retry_done, $sformatf("service slot %0d", slot));
    disable target_retry;
    if (!retry_seq.response_valid || !retry_seq.observed_ack)
      `uvm_fatal("IBI_CTRL_MULTI_RETRY",
                 $sformatf("Controller did not service slot %0d address 0x%02h",
                           slot, target_addr))

    wait_irq(1'b1, $sformatf("wait for slot %0d HCI IBI IRQ", slot));
    hci_helper.read_ibi_record(descriptor, hci_data, this);
    check_record(descriptor, hci_data, target_addr, target_mdb,
                 $sformatf("slot %0d HCI record", slot));
    wait_scoreboard_completion(expected_completion,
      $sformatf("wait for slot %0d scoreboard completion", slot));
    wait_irq(1'b0, $sformatf("wait for slot %0d IRQ clear", slot));
  endtask
`endif
`endif

  virtual task body();
    super.body();
    if (!vseq_ctx.cfg.has_rtl)
      `uvm_fatal("IBI_CTRL_MULTI_MODE",
                 "Controller multi-target test requires native I3C RTL mode")
    if (vseq_ctx.cfg.ibi_dut_role != I3C_IBI_DUT_CONTROLLER)
      `uvm_fatal("IBI_CTRL_MULTI_ROLE",
                 "Controller multi-target vseq requires DUT-controller role")

`ifdef I3C_DV_NATIVE_RTL
`ifdef I3C_DV_NATIVE_RAL
    begin
      i3c_controller_hci_helper #(TB_ADDR_WIDTH, TB_DATA_WIDTH) hci_helper;
      i3c_target_send_ibi_seq target_seq_0;
      i3c_target_send_ibi_seq target_seq_1;
      i3c_target_send_ibi_seq target_seq_2;
      i3c_target_send_ibi_seq target_seq_3;
      uvm_event armed_0;
      uvm_event armed_1;
      uvm_event armed_2;
      uvm_event armed_3;
      bit done_0;
      bit done_1;
      bit done_2;
      bit done_3;
      bit [6:0] address[4];
      bit [7:0] mdb[4];
      bit [6:0] ordered_addr[4];
      bit [6:0] swap_addr;
      int unsigned winner_slot;
      bit [31:0] interrupt_status;
      bit [31:0] descriptor;
      byte unsigned hci_data[$];

      for (int unsigned slot = 0; slot < TARGET_COUNT; slot++) begin
        if (vseq_ctx.i3c_target_sqr[slot] == null)
          `uvm_fatal("IBI_CTRL_MULTI_SQR",
                     $sformatf("Target sequencer slot %0d is required", slot))
        address[slot] = vseq_ctx.cfg.ibi_target_addr_by_slot[slot];
        mdb[slot] = vseq_ctx.cfg.ibi_basic_mdb ^ (8'h3c * slot);
        ordered_addr[slot] = address[slot];
      end
      for (int unsigned left = 0; left < TARGET_COUNT; left++) begin
        for (int unsigned right = left + 1; right < TARGET_COUNT; right++) begin
          if (ordered_addr[right] < ordered_addr[left]) begin
            swap_addr = ordered_addr[left];
            ordered_addr[left] = ordered_addr[right];
            ordered_addr[right] = swap_addr;
          end
        end
      end
      winner_slot = slot_for_addr(ordered_addr[0]);

      hci_helper = vseq_ctx.i3c_controller_hci_helper;
      if (hci_helper == null)
        `uvm_fatal("IBI_CTRL_MULTI_HELPER",
                   "Controller HCI helper is not available")
      hci_helper.initialize_controller_ibi(address[0], 0, this);
      hci_helper.program_dat_entry(1, address[1], '0, 1'b0, 1'b1, this);
      hci_helper.program_dat_entry(2, address[2], '0, 1'b0, 1'b1, this);
      hci_helper.program_dat_entry(3, address[3], '0, 1'b0, 1'b1, this);
      wait_bus_idle("wait for idle bus before four-Target IBI");
      hci_helper.wait_bus_available(this);
      wait_irq(1'b0, "verify four-Target IBI IRQ initially low");
      hci_helper.enable_broadcast_header(this);
      // This internal HCI command configures the next transfer; it does not
      // emit a standalone 0x7e frame. Keep the bus idle for T_AVAL before
      // arming targets, then let the private-write command open arbitration.
      hci_helper.wait_bus_available(this);

      target_seq_0 = i3c_target_send_ibi_seq::type_id::create("target_seq_0");
      target_seq_1 = i3c_target_send_ibi_seq::type_id::create("target_seq_1");
      target_seq_2 = i3c_target_send_ibi_seq::type_id::create("target_seq_2");
      target_seq_3 = i3c_target_send_ibi_seq::type_id::create("target_seq_3");
      target_seq_0.target_addr = address[0];
      target_seq_1.target_addr = address[1];
      target_seq_2.target_addr = address[2];
      target_seq_3.target_addr = address[3];
      target_seq_0.mdb = mdb[0];
      target_seq_1.mdb = mdb[1];
      target_seq_2.mdb = mdb[2];
      target_seq_3.mdb = mdb[3];
      // All requesters wait for the Controller transfer. Descriptor commit is
      // held until every driver has crossed the barrier and is START-ready.
      target_seq_0.start_on_idle = 1'b0;
      target_seq_1.start_on_idle = 1'b0;
      target_seq_2.start_on_idle = 1'b0;
      target_seq_3.start_on_idle = 1'b0;
      armed_0 = uvm_event_pool::get_global(
        $sformatf("%s_0", I3C_TARGET_IBI_SLOT_ARMED_EVENT));
      armed_1 = uvm_event_pool::get_global(
        $sformatf("%s_1", I3C_TARGET_IBI_SLOT_ARMED_EVENT));
      armed_2 = uvm_event_pool::get_global(
        $sformatf("%s_2", I3C_TARGET_IBI_SLOT_ARMED_EVENT));
      armed_3 = uvm_event_pool::get_global(
        $sformatf("%s_3", I3C_TARGET_IBI_SLOT_ARMED_EVENT));
      armed_0.reset();
      armed_1.reset();
      armed_2.reset();
      armed_3.reset();
      done_0 = 1'b0;
      done_1 = 1'b0;
      done_2 = 1'b0;
      done_3 = 1'b0;
      vseq_ctx.cfg.clear_ibi_target_driver_state();
      vseq_ctx.cfg.ibi_target_driver_barrier_enable = 1'b1;
      fork : concurrent_targets
        begin target_seq_0.start(vseq_ctx.i3c_target_sqr[0]); done_0 = 1'b1; end
        begin target_seq_1.start(vseq_ctx.i3c_target_sqr[1]); done_1 = 1'b1; end
        begin target_seq_2.start(vseq_ctx.i3c_target_sqr[2]); done_2 = 1'b1; end
        begin target_seq_3.start(vseq_ctx.i3c_target_sqr[3]); done_3 = 1'b1; end
      join_none
      armed_0.wait_on();
      armed_1.wait_on();
      armed_2.wait_on();
      armed_3.wait_on();
      // Release the drivers first and wait until all four can consume the next
      // START. Only then submit the complete HCI descriptor/data pair. This
      // prevents the low command word from being consumed while Targets remain
      // behind the barrier and avoids relying on the high word as a commit.
      @(posedge vseq_ctx.cfg.vif.clk);
      wait_bus_idle("confirm idle bus after all four Targets are armed");
      vseq_ctx.cfg.ibi_requester_count = TARGET_COUNT;
      vseq_ctx.cfg.ibi_arb_outcome = 2'd1;
      vseq_ctx.cfg.ibi_bus_state = 2'd1;
      vseq_ctx.cfg.vif.i3c_controller_expected_addr = ordered_addr[0];
      vseq_ctx.cfg.ibi_target_driver_release = 1'b1;
      wait_four_targets_ready();
      hci_helper.issue_dat_private_write(winner_slot, 8'hc3, 4'h1, this);
      wait_four_targets(done_0, done_1, done_2, done_3);
      disable concurrent_targets;
      vseq_ctx.cfg.ibi_target_driver_barrier_enable = 1'b0;
      vseq_ctx.cfg.ibi_target_driver_release = 1'b0;

      // Publish one coherent system-level arbitration snapshot. Sequence is
      // incremented last so SVA never observes a partially updated vector.
      vseq_ctx.cfg.vif.i3c_sva_requester_active = 4'b1111;
      vseq_ctx.cfg.vif.i3c_sva_requester_winner = '0;
      vseq_ctx.cfg.vif.i3c_sva_requester_released = '0;
      for (int unsigned slot = 0; slot < TARGET_COUNT; slot++) begin
        vseq_ctx.cfg.vif.i3c_sva_requester_winner[slot] =
          vseq_ctx.cfg.ibi_target_driver_arbitration_won[slot];
        vseq_ctx.cfg.vif.i3c_sva_requester_released[slot] =
          vseq_ctx.cfg.ibi_target_driver_released[slot];
      end
      vseq_ctx.cfg.vif.i3c_sva_arbitration_seq++;

      `uvm_info("IBI_CTRL_MULTI_TELEMETRY",
                $sformatf("targets_ready=4 command_issued_after_ready=1 expected_winner=slot%0d/0x%02h resolved=0x%02h/0x%02h/0x%02h/0x%02h ack=%0b/%0b/%0b/%0b won=%0b/%0b/%0b/%0b released=%0b/%0b/%0b/%0b DAT_readback=PASS",
                          winner_slot, ordered_addr[0],
                          vseq_ctx.cfg.ibi_target_driver_resolved_addr[0],
                          vseq_ctx.cfg.ibi_target_driver_resolved_addr[1],
                          vseq_ctx.cfg.ibi_target_driver_resolved_addr[2],
                          vseq_ctx.cfg.ibi_target_driver_resolved_addr[3],
                          vseq_ctx.cfg.ibi_target_driver_ack[0],
                          vseq_ctx.cfg.ibi_target_driver_ack[1],
                          vseq_ctx.cfg.ibi_target_driver_ack[2],
                          vseq_ctx.cfg.ibi_target_driver_ack[3],
                          vseq_ctx.cfg.ibi_target_driver_arbitration_won[0],
                          vseq_ctx.cfg.ibi_target_driver_arbitration_won[1],
                          vseq_ctx.cfg.ibi_target_driver_arbitration_won[2],
                          vseq_ctx.cfg.ibi_target_driver_arbitration_won[3],
                          vseq_ctx.cfg.ibi_target_driver_released[0],
                          vseq_ctx.cfg.ibi_target_driver_released[1],
                          vseq_ctx.cfg.ibi_target_driver_released[2],
                          vseq_ctx.cfg.ibi_target_driver_released[3]),
                UVM_NONE)

      if ((target_seq_0.observed_ack + target_seq_1.observed_ack +
           target_seq_2.observed_ack + target_seq_3.observed_ack) != 1)
        `uvm_fatal("IBI_CTRL_MULTI_WINNER",
                   $sformatf("Expected one ACK, observed=%0b/%0b/%0b/%0b",
                             target_seq_0.observed_ack,
                             target_seq_1.observed_ack,
                             target_seq_2.observed_ack,
                             target_seq_3.observed_ack))
      if (((winner_slot == 0) && !target_seq_0.observed_ack) ||
          ((winner_slot == 1) && !target_seq_1.observed_ack) ||
          ((winner_slot == 2) && !target_seq_2.observed_ack) ||
          ((winner_slot == 3) && !target_seq_3.observed_ack))
        `uvm_fatal("IBI_CTRL_MULTI_ARBITRATION",
                   $sformatf("Lowest address 0x%02h did not win arbitration",
                             ordered_addr[0]))
      if ((vseq_ctx.cfg.ibi_controller_arbitration_losses != 3) ||
          (vseq_ctx.cfg.ibi_controller_loser_release_checks != 3) ||
          (vseq_ctx.cfg.ibi_controller_loser_release_failures != 0))
        `uvm_fatal("IBI_CTRL_MULTI_RELEASE",
                   $sformatf("Expected three clean loser releases; losses=%0d checks=%0d failures=%0d",
                             vseq_ctx.cfg.ibi_controller_arbitration_losses,
                             vseq_ctx.cfg.ibi_controller_loser_release_checks,
                             vseq_ctx.cfg.ibi_controller_loser_release_failures))

      wait_irq(1'b1, "wait for arbitration winner HCI IBI IRQ");
      hci_helper.read_ibi_status(interrupt_status, this);
      if (!interrupt_status[2])
        `uvm_fatal("IBI_CTRL_MULTI_IRQ",
                   "Winner did not set IBI_STATUS_THLD_STAT")
      hci_helper.read_ibi_record(descriptor, hci_data, this);
      check_record(descriptor, hci_data, ordered_addr[0], mdb[winner_slot],
                   "winner HCI record");
      wait_scoreboard_completion(1, "wait for winner scoreboard completion");
      wait_irq(1'b0, "wait for winner IRQ clear");

      service_target(hci_helper, ordered_addr[1],
                     mdb[slot_for_addr(ordered_addr[1])], 2);
      service_target(hci_helper, ordered_addr[2],
                     mdb[slot_for_addr(ordered_addr[2])], 3);
      service_target(hci_helper, ordered_addr[3],
                     mdb[slot_for_addr(ordered_addr[3])], 4);

      if ((vseq_ctx.cfg.ibi_controller_expected_events != 4) ||
          (vseq_ctx.cfg.ibi_controller_actual_events != 4))
        `uvm_fatal("IBI_CTRL_MULTI_EVENT_COUNT",
                   $sformatf("Expected/actual Controller events must be 4/4, got %0d/%0d",
                             vseq_ctx.cfg.ibi_controller_expected_events,
                             vseq_ctx.cfg.ibi_controller_actual_events))
      if (vseq_ctx.cfg.ibi_sb_mismatch_count != 0)
        `uvm_error("IBI_CTRL_MULTI_SB",
                   $sformatf("Controller multi-target scoreboard mismatches=%0d",
                             vseq_ctx.cfg.ibi_sb_mismatch_count))
      `uvm_info("IBI_CTRL_MULTI_TARGET",
                $sformatf("Four-Target arbitration winner=0x%02h; losers=0x%02h/0x%02h/0x%02h released SDA and were serviced later",
                          ordered_addr[0], ordered_addr[1], ordered_addr[2],
                          ordered_addr[3]),
                UVM_LOW)
    end
`else
    `uvm_fatal("IBI_CTRL_MULTI_RAL_BUILD",
               "Controller multi-target test requires I3C_DV_NATIVE_RAL")
`endif
`else
    `uvm_fatal("IBI_CTRL_MULTI_RTL_BUILD",
               "Controller multi-target test requires I3C_DV_NATIVE_RTL")
`endif
  endtask
endclass : i3c_ibi_controller_rx_multi_target_vseq

`endif // I3C_IBI_CONTROLLER_RX_MULTI_TARGET_VSEQ_SV
