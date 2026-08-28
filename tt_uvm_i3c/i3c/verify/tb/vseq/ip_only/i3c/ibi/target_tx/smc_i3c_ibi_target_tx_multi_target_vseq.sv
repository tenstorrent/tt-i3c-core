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
// File        : smc_i3c_ibi_target_tx_multi_target_vseq.sv
// Description : DUT-Target IBI arbitration against a second UVM Target.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-04
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_TARGET_TX_MULTI_TARGET_VSEQ_SV
`define SMC_I3C_IBI_TARGET_TX_MULTI_TARGET_VSEQ_SV

class smc_i3c_ibi_target_tx_multi_target_vseq extends smc_i3c_ibi_base_vseq;
  `uvm_object_utils(smc_i3c_ibi_target_tx_multi_target_vseq)

  function new(string name = "smc_i3c_ibi_target_tx_multi_target_vseq");
    super.new(name);
  endfunction

`ifdef SMC_USE_I3C_RTL
`ifdef SMC_USE_I3C_RAL
  protected task check_host_response(
      input smc_i3c_host_respond_ibi_seq host_seq,
      input bit [6:0] expected_addr,
      input bit [7:0] expected_mdb,
      input string operation);
    if (!host_seq.response_valid)
      `uvm_fatal("IBI_MULTI_HOST",
                 $sformatf("%s returned no valid IBI response", operation))
    if (host_seq.response_addr != expected_addr)
      `uvm_fatal("IBI_MULTI_ADDRESS",
                 $sformatf("%s expected winner DA=0x%02h, observed DA=0x%02h",
                           operation, expected_addr,
                           host_seq.response_addr))
    if ((host_seq.response_data.size() != 1) ||
        (host_seq.response_data[0] != expected_mdb))
      `uvm_fatal("IBI_MULTI_DATA",
                 $sformatf("%s expected one MDB byte 0x%02h, observed bytes=%0d first=0x%02h",
                           operation, expected_mdb,
                           host_seq.response_data.size(),
                           (host_seq.response_data.size() == 0) ?
                             8'h00 : host_seq.response_data[0]))
  endtask

  protected task wait_for_pair(
      ref bit first_done,
      ref bit second_done,
      input string operation);
    if (first_done && second_done)
      return;
    repeat (vseq_ctx.cfg.ibi_timeout_cycles) begin
      @(posedge vseq_ctx.cfg.vif.clk);
      if (first_done && second_done)
        return;
    end
    `uvm_fatal("IBI_MULTI_TIMEOUT",
               $sformatf("%s timed out: first_done=%0b second_done=%0b",
                         operation, first_done, second_done))
  endtask

  // Check the resolved bus as well as the per-driver ownership controls. The
  // first arbitration is initiated by the DUT Target; the later loser-service
  // transaction is initiated by the secondary UVM Target.
  protected task check_target_start_timing(
      input bit expect_dut_owner,
      input string operation);
    realtime sda_fall_time;
    realtime scl_fall_time;
    realtime hold_time;
    int unsigned minimum_hold_ns;
    int unsigned minimum_addr_launch_ns;
    bit timing_done;
    bit first_scl_fall_seen;

    minimum_hold_ns = vseq_ctx.cfg.i3c_cfg.tc.i3c_tc.tHoldStart;
    minimum_addr_launch_ns =
      vseq_ctx.cfg.i3c_cfg.tc.i3c_tc.tAddrLaunchDelay;
    if ((vseq_ctx.cfg.i3c_vif.scl_i !== 1'b1) ||
        (vseq_ctx.cfg.i3c_vif.sda_i !== 1'b1))
      `uvm_fatal("IBI_MULTI_START_IDLE",
                 $sformatf("%s started without an idle SCL/SDA=1/1 bus; observed %b/%b",
                           operation, vseq_ctx.cfg.i3c_vif.scl_i,
                           vseq_ctx.cfg.i3c_vif.sda_i))

    timing_done = 1'b0;
    first_scl_fall_seen = 1'b0;
    fork : start_timing_timeout_guard
      begin
        @(negedge vseq_ctx.cfg.i3c_vif.sda_i);
        sda_fall_time = $realtime;
        if (vseq_ctx.cfg.i3c_vif.scl_i !== 1'b1)
          `uvm_fatal("IBI_MULTI_START_CONDITION",
                     $sformatf("%s SDA fell while SCL was not high",
                               operation))
        if ($isunknown({vseq_ctx.cfg.i3c_vif.scl_i,
                        vseq_ctx.cfg.i3c_vif.sda_i}))
          `uvm_fatal("IBI_MULTI_START_UNKNOWN",
                     $sformatf("%s observed X/Z on the resolved START bus",
                               operation))
        if ((vseq_ctx.cfg.i3c_vif.host_sda_o !== 1'b1) ||
            (vseq_ctx.cfg.i3c_vif.host_sda_pp_en !== 1'b0))
          `uvm_fatal("IBI_MULTI_START_CONTENTION",
                     $sformatf("%s UVM Host drove SDA during Target START",
                               operation))

        if (expect_dut_owner) begin
          if (vseq_ctx.cfg.vif.i3c_sda_oe !== 1'b1)
            `uvm_fatal("IBI_MULTI_START_OWNER",
                       $sformatf("%s expected DUT Target to own SDA START",
                                 operation))
          if ((vseq_ctx.cfg.i3c_secondary_vif.device_sda_o !== 1'b1) ||
              (vseq_ctx.cfg.i3c_secondary_vif.device_sda_pp_en !== 1'b0))
            `uvm_fatal("IBI_MULTI_START_CONTENTION",
                       $sformatf("%s secondary UVM Target drove SDA during DUT START",
                                 operation))
        end else begin
          if (vseq_ctx.cfg.vif.i3c_sda_oe !== 1'b0)
            `uvm_fatal("IBI_MULTI_START_CONTENTION",
                       $sformatf("%s DUT Target drove SDA during secondary Target START",
                                 operation))
          if ((vseq_ctx.cfg.i3c_secondary_vif.device_sda_o !== 1'b0) ||
              (vseq_ctx.cfg.i3c_secondary_vif.device_sda_pp_en !== 1'b0))
            `uvm_fatal("IBI_MULTI_START_OWNER",
                       $sformatf("%s expected secondary UVM Target to own SDA START in open-drain mode",
                                 operation))
        end

        fork : stable_start_guard
          begin
            @(negedge vseq_ctx.cfg.i3c_vif.scl_i);
            scl_fall_time = $realtime;
            first_scl_fall_seen = 1'b1;
            if ((vseq_ctx.cfg.i3c_vif.scl_o !== 1'b0) ||
                (vseq_ctx.cfg.i3c_vif.scl_pp_en !== 1'b1))
              `uvm_fatal("IBI_MULTI_SCL_OWNER",
                         $sformatf("%s first SCL falling edge was not driven Push-Pull by the UVM Host",
                                   operation))
            if ((vseq_ctx.cfg.i3c_vif.host_sda_o !== 1'b0) ||
                (vseq_ctx.cfg.i3c_vif.host_sda_pp_en !== 1'b0))
              `uvm_fatal("IBI_MULTI_SDA_HANDOFF",
                         $sformatf("%s UVM Host did not take over the START-low SDA level in Open-Drain before completing START",
                                   operation))
            hold_time = scl_fall_time - sda_fall_time;
            if (hold_time < realtime'(minimum_hold_ns))
              `uvm_fatal("IBI_MULTI_START_HOLD",
                         $sformatf("%s START hold=%0.3f ns is below configured tHoldStart=%0d ns",
                                   operation, hold_time,
                                   minimum_hold_ns))

            fork : address_launch_guard
              begin
                #(minimum_addr_launch_ns * 1ns);
              end
              begin
                @(posedge vseq_ctx.cfg.i3c_vif.sda_i);
                if (($realtime - scl_fall_time) <
                    realtime'(minimum_addr_launch_ns))
                  `uvm_fatal("IBI_MULTI_ADDR_LAUNCH",
                             $sformatf("%s SDA changed %0.3f ns after first SCL falling edge; configured address-launch minimum=%0d ns",
                                       operation,
                                       $realtime - scl_fall_time,
                                       minimum_addr_launch_ns))
              end
            join_any
            disable address_launch_guard;
            timing_done = 1'b1;
          end
          begin
            forever begin
              @(posedge vseq_ctx.cfg.i3c_vif.sda_i);
              if (!first_scl_fall_seen)
                `uvm_fatal("IBI_MULTI_START_GLITCH",
                           $sformatf("%s SDA released before the first SCL falling edge",
                                     operation))
            end
          end
          begin
            forever begin
              @(vseq_ctx.cfg.i3c_vif.scl_i or
                vseq_ctx.cfg.i3c_vif.sda_i);
              if ($isunknown({vseq_ctx.cfg.i3c_vif.scl_i,
                              vseq_ctx.cfg.i3c_vif.sda_i}))
                `uvm_fatal("IBI_MULTI_START_UNKNOWN",
                           $sformatf("%s observed X/Z before the first SCL falling edge",
                                     operation))
            end
          end
        join_any
        disable stable_start_guard;
      end
      begin
        repeat (vseq_ctx.cfg.ibi_timeout_cycles)
          @(posedge vseq_ctx.cfg.vif.clk);
        if (!timing_done)
          `uvm_fatal("IBI_MULTI_START_TIMEOUT",
                     $sformatf("%s timed out waiting for a complete START phase",
                               operation))
      end
    join_any
    disable start_timing_timeout_guard;

    if (!timing_done)
      `uvm_fatal("IBI_MULTI_START_INCOMPLETE",
                 $sformatf("%s START timing checker did not complete",
                           operation))
    `uvm_info("IBI_MULTI_START_TIMING",
              $sformatf("%s owner=%s hold=%0.3f ns minimum=%0d ns address-launch minimum=%0d ns",
                        operation,
                        expect_dut_owner ? "DUT Target" : "secondary UVM Target",
                        hold_time, minimum_hold_ns,
                        minimum_addr_launch_ns),
              UVM_LOW)
  endtask
`endif
`endif

  virtual task body();
    super.body();

    if (!vseq_ctx.cfg.has_rtl)
      `uvm_fatal("IBI_MULTI_MODE",
                 "smc_i3c_ibi_target_tx_multi_target_test requires DUT_MODE=rtl")
    if (vseq_ctx.cfg.ibi_dut_role != SMC_I3C_IBI_DUT_TARGET)
      `uvm_fatal("IBI_MULTI_ROLE",
                 "smc_i3c_ibi_target_tx_multi_target_test verifies DUT-Target transmit behavior")

`ifndef SMC_USE_I3C_RTL
    `uvm_fatal("IBI_MULTI_RTL_BUILD",
               "Multi-Target IBI arbitration requires SMC_USE_I3C_RTL")
`elsif SMC_USE_I3C_RAL
    begin
      smc_i3c_ral_model ral;
      smc_i3c_host_respond_ibi_seq winner_host_seq;
      smc_i3c_host_respond_ibi_seq loser_host_seq;
      smc_i3c_target_send_ibi_seq competitor_seq;
      smc_i3c_target_send_ibi_seq tertiary_seq;
      smc_i3c_target_send_ibi_seq competitor_retry_seq;
      smc_i3c_target_send_ibi_seq tertiary_retry_seq;
      uvm_event host_armed_event;
      uvm_event secondary_armed_event;
      uvm_event tertiary_armed_event;
      uvm_reg_data_t field_value;
      uvm_reg_data_t ibi_descriptor;
      bit winner_host_done;
      bit competitor_done;
      bit tertiary_done;
      bit winner_start_timing_done;
      bit loser_host_done;
      bit competitor_retry_done;
      bit tertiary_retry_done;
      bit loser_start_timing_done;
      bit [6:0] dut_addr;
      bit [6:0] competitor_addr;
      bit [6:0] tertiary_addr;
      bit [7:0] dut_mdb;
      bit [7:0] competitor_mdb;
      bit [7:0] tertiary_mdb;
      int unsigned completion_before;
      int unsigned mismatch_before;
      virtual i3c_if tertiary_target_vif;

      if ((vseq_ctx.i3c_sqr == null) ||
          (vseq_ctx.i3c_target_sqr[1] == null) ||
          (vseq_ctx.i3c_target_sqr[2] == null))
        `uvm_fatal("IBI_MULTI_SQR",
                   "The UVM Host and two UVM Target sequencers are required")
      if (!vseq_ctx.cfg.has_ibi_scoreboard)
        `uvm_fatal("IBI_MULTI_SCOREBOARD",
                   "DUT-Target descriptor scoreboard is required")

      ral = get_i3c_ral_model();
      dut_addr = vseq_ctx.cfg.ibi_target_addr;
      competitor_addr = vseq_ctx.cfg.ibi_secondary_target_addr;
      tertiary_addr = vseq_ctx.cfg.ibi_target_addr_by_slot[2];
      dut_mdb = vseq_ctx.cfg.ibi_basic_mdb;
      competitor_mdb = vseq_ctx.cfg.ibi_basic_mdb ^ 8'h3c;
      tertiary_mdb = vseq_ctx.cfg.ibi_basic_mdb ^ 8'h69;
      if ((competitor_addr <= dut_addr) ||
          (tertiary_addr <= competitor_addr))
        `uvm_fatal("IBI_MULTI_ORDER_CFG",
                   $sformatf("Expected DUT < secondary < tertiary addresses, got 0x%02h/0x%02h/0x%02h",
                             dut_addr, competitor_addr, tertiary_addr))

      completion_before = vseq_ctx.cfg.ibi_sb_completion_count;
      mismatch_before = vseq_ctx.cfg.ibi_sb_mismatch_count;
      vseq_ctx.cfg.ibi_expected_ack = 1'b1;
      vseq_ctx.cfg.ibi_expected_terminal_status = IBI_STATUS_SUCCESS;
      initialize_target_ibi(ral);
      write_field(ral.I3C_EC.TTI.INTERRUPT_ENABLE.IBI_DONE_EN, 1,
                  "enable DUT Target IBI_DONE interrupt");
      clear_w1c_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 1,
                      "clear stale DUT Target IBI_DONE");
      wait_irq(1'b0, "check initial multi-Target IRQ state");

      winner_host_seq = smc_i3c_host_respond_ibi_seq::type_id::create(
        "winner_host_seq");
      winner_host_seq.ibi_ack = 1'b1;
      winner_host_seq.rx_byte_count = 1;
      competitor_seq = smc_i3c_target_send_ibi_seq::type_id::create(
        "competitor_seq");
      competitor_seq.target_addr = competitor_addr;
      competitor_seq.mdb = competitor_mdb;
      // Arm on an externally generated START. The DUT Target owns START for
      // the first attempt; both Targets then drive the address in arbitration.
      competitor_seq.start_on_idle = 1'b0;
      tertiary_seq = smc_i3c_target_send_ibi_seq::type_id::create(
        "tertiary_seq");
      tertiary_seq.target_addr = tertiary_addr;
      tertiary_seq.mdb = tertiary_mdb;
      tertiary_seq.start_on_idle = 1'b0;
      ibi_descriptor = uvm_reg_data_t'(dut_mdb) << 24;

      host_armed_event = uvm_event_pool::get_global(
        SMC_I3C_HOST_IBI_ARMED_EVENT);
      secondary_armed_event = uvm_event_pool::get_global(
        $sformatf("%s_1", SMC_I3C_TARGET_IBI_SLOT_ARMED_EVENT));
      tertiary_armed_event = uvm_event_pool::get_global(
        $sformatf("%s_2", SMC_I3C_TARGET_IBI_SLOT_ARMED_EVENT));
      host_armed_event.reset();
      secondary_armed_event.reset();
      tertiary_armed_event.reset();
      winner_host_done = 1'b0;
      competitor_done = 1'b0;
      tertiary_done = 1'b0;
      winner_start_timing_done = 1'b0;

      fork : concurrent_arbitration
        begin
          winner_host_seq.start(vseq_ctx.i3c_sqr);
          winner_host_done = 1'b1;
        end
        begin
          competitor_seq.start(vseq_ctx.i3c_target_sqr[1]);
          competitor_done = 1'b1;
        end
        begin
          tertiary_seq.start(vseq_ctx.i3c_target_sqr[2]);
          tertiary_done = 1'b1;
        end
        begin
          host_armed_event.wait_on();
          secondary_armed_event.wait_on();
          tertiary_armed_event.wait_on();
          vseq_ctx.cfg.ibi_requester_count = 3;
          vseq_ctx.cfg.ibi_arb_outcome = 2'd1;
          vseq_ctx.cfg.ibi_bus_state = 2'd0;
          write_register(ral.I3C_EC.TTI.IBI_PORT, ibi_descriptor,
                         "queue DUT MDB while both arbitration participants are armed");
        end
        begin
          check_target_start_timing(
            1'b1, "concurrent DUT Target IBI START");
          winner_start_timing_done = 1'b1;
        end
      join_none
      wait_for_pair(winner_host_done, competitor_done,
                    "concurrent DUT/UVM Target arbitration");
      wait_for_pair(winner_host_done, tertiary_done,
                    "concurrent DUT/tertiary Target arbitration");
      wait_for_pair(winner_host_done, winner_start_timing_done,
                    "DUT Target START timing check");
      disable concurrent_arbitration;

      check_host_response(winner_host_seq, dut_addr, dut_mdb,
                          "concurrent arbitration winner");
      if (!competitor_seq.response_valid)
        `uvm_fatal("IBI_MULTI_COMPETITOR",
                   "Secondary UVM Target produced no arbitration response")
      if (competitor_seq.observed_ack)
        `uvm_fatal("IBI_MULTI_SINGLE_WINNER",
                   "Secondary UVM Target was ACKed even though the lower DUT address won")
      if (!tertiary_seq.response_valid || tertiary_seq.observed_ack)
        `uvm_fatal("IBI_MULTI_SINGLE_WINNER",
                   "Tertiary UVM Target did not lose cleanly to the lower DUT address")
      if ((vseq_ctx.cfg.i3c_secondary_vif.device_sda_o !== 1'b1) ||
          (vseq_ctx.cfg.i3c_secondary_vif.device_sda_pp_en !== 1'b0))
        `uvm_fatal("IBI_MULTI_LOSER_RELEASE",
                   "Secondary UVM Target did not release SDA after losing arbitration")
      tertiary_target_vif = i3c_vif_for_slot(2);
      if ((tertiary_target_vif.device_sda_o !== 1'b1) ||
          (tertiary_target_vif.device_sda_pp_en !== 1'b0))
        `uvm_fatal("IBI_MULTI_LOSER_RELEASE",
                   "Tertiary UVM Target did not release SDA after losing arbitration")

      wait_irq(1'b1, "wait for DUT winner IBI_DONE IRQ");
      expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 1,
                   "confirm DUT winner IBI_DONE source");
      read_field(ral.I3C_EC.TTI.STATUS.LAST_IBI_STATUS, field_value,
                 "read DUT winner LAST_IBI_STATUS");
      if (field_value != uvm_reg_data_t'(IBI_STATUS_SUCCESS))
        `uvm_fatal("IBI_MULTI_DUT_STATUS",
                   $sformatf("DUT winner expected SUCCESS, got LAST_IBI_STATUS=0x%0h",
                             field_value))
      wait_irq(1'b0, "wait for DUT winner IRQ clear");
      wait_scoreboard_completion(completion_before + 1,
                                 "wait for DUT winner descriptor match");
      if (vseq_ctx.cfg.ibi_sb_mismatch_count != mismatch_before)
        `uvm_fatal("IBI_MULTI_DUT_SCOREBOARD",
                   $sformatf("DUT winner added %0d scoreboard mismatch(es)",
                             vseq_ctx.cfg.ibi_sb_mismatch_count -
                             mismatch_before))
      wait_bus_idle("wait for idle bus after DUT arbitration winner");

      // Service the losing external Target in a separate transaction. This
      // proves that it released cleanly rather than becoming wedged after the
      // first arbitration. It is checked directly and is intentionally not a
      // DUT descriptor-scoreboard transaction.
      loser_host_seq = smc_i3c_host_respond_ibi_seq::type_id::create(
        "loser_host_seq");
      loser_host_seq.ibi_ack = 1'b1;
      loser_host_seq.rx_byte_count = 1;
      competitor_retry_seq = smc_i3c_target_send_ibi_seq::type_id::create(
        "competitor_retry_seq");
      competitor_retry_seq.target_addr = competitor_addr;
      competitor_retry_seq.mdb = competitor_mdb;
      competitor_retry_seq.start_on_idle = 1'b1;
      host_armed_event.reset();
      loser_host_done = 1'b0;
      competitor_retry_done = 1'b0;
      loser_start_timing_done = 1'b0;
      vseq_ctx.cfg.ibi_requester_count = 1;
      vseq_ctx.cfg.ibi_arb_outcome = 2'd0;

      fork : loser_service
        begin
          loser_host_seq.start(vseq_ctx.i3c_sqr);
          loser_host_done = 1'b1;
        end
        begin
          host_armed_event.wait_on();
          competitor_retry_seq.start(vseq_ctx.i3c_secondary_sqr);
          competitor_retry_done = 1'b1;
        end
        begin
          check_target_start_timing(
            1'b0, "later secondary UVM Target IBI START");
          loser_start_timing_done = 1'b1;
        end
      join_none
      wait_for_pair(loser_host_done, competitor_retry_done,
                    "later service of losing UVM Target");
      wait_for_pair(loser_host_done, loser_start_timing_done,
                    "secondary UVM Target START timing check");
      disable loser_service;

      check_host_response(loser_host_seq, competitor_addr, competitor_mdb,
                          "later loser service");
      if (!competitor_retry_seq.response_valid ||
          !competitor_retry_seq.observed_ack)
        `uvm_fatal("IBI_MULTI_LOSER_SERVICE",
                   "Secondary UVM Target was not ACKed when serviced later")
      wait_bus_idle("check idle bus after later loser service");
      wait_irq(1'b0, "ensure external Target IBI does not raise DUT Target IRQ");
      expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 0,
                   "ensure external Target did not set DUT IBI_DONE");
      if (vseq_ctx.cfg.ibi_sb_completion_count != (completion_before + 1))
        `uvm_fatal("IBI_MULTI_ISOLATION",
                   $sformatf("External Target altered DUT descriptor scoreboard count: expected=%0d actual=%0d",
                             completion_before + 1,
                             vseq_ctx.cfg.ibi_sb_completion_count))
      if (vseq_ctx.cfg.ibi_sb_mismatch_count != mismatch_before)
        `uvm_fatal("IBI_MULTI_ISOLATION",
                   "External Target traffic created a DUT descriptor mismatch")

      // Service the second losing UVM Target independently. Keeping each
      // loser in a separate transaction proves both device drivers released
      // arbitration state and can be re-entered without cross-slot leakage.
      loser_host_seq = smc_i3c_host_respond_ibi_seq::type_id::create(
        "tertiary_loser_host_seq");
      loser_host_seq.ibi_ack = 1'b1;
      loser_host_seq.rx_byte_count = 1;
      tertiary_retry_seq = smc_i3c_target_send_ibi_seq::type_id::create(
        "tertiary_retry_seq");
      tertiary_retry_seq.target_addr = tertiary_addr;
      tertiary_retry_seq.mdb = tertiary_mdb;
      tertiary_retry_seq.start_on_idle = 1'b1;
      host_armed_event.reset();
      loser_host_done = 1'b0;
      tertiary_retry_done = 1'b0;
      vseq_ctx.cfg.ibi_requester_count = 1;
      vseq_ctx.cfg.ibi_arb_outcome = 2'd0;

      fork : tertiary_loser_service
        begin
          loser_host_seq.start(vseq_ctx.i3c_sqr);
          loser_host_done = 1'b1;
        end
        begin
          host_armed_event.wait_on();
          tertiary_retry_seq.start(vseq_ctx.i3c_target_sqr[2]);
          tertiary_retry_done = 1'b1;
        end
      join_none
      wait_for_pair(loser_host_done, tertiary_retry_done,
                    "later service of tertiary UVM Target");
      disable tertiary_loser_service;

      check_host_response(loser_host_seq, tertiary_addr, tertiary_mdb,
                          "later tertiary loser service");
      if (!tertiary_retry_seq.response_valid ||
          !tertiary_retry_seq.observed_ack)
        `uvm_fatal("IBI_MULTI_LOSER_SERVICE",
                   "Tertiary UVM Target was not ACKed when serviced later")
      wait_bus_idle("check idle bus after tertiary loser service");
      wait_irq(1'b0, "ensure tertiary Target IBI does not raise DUT Target IRQ");
      expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 0,
                   "ensure tertiary Target did not set DUT IBI_DONE");
      if (vseq_ctx.cfg.ibi_sb_completion_count != (completion_before + 1))
        `uvm_fatal("IBI_MULTI_ISOLATION",
                   "Tertiary Target altered DUT descriptor scoreboard count")
      if (vseq_ctx.cfg.ibi_sb_mismatch_count != mismatch_before)
        `uvm_fatal("IBI_MULTI_ISOLATION",
                   "Tertiary Target traffic created a DUT descriptor mismatch")

      `uvm_info("IBI_MULTI_TARGET_PASS",
                $sformatf("DUT Target DA=0x%02h won three-requester arbitration; UVM Targets 0x%02h/0x%02h released SDA and were serviced later",
                          dut_addr, competitor_addr, tertiary_addr),
                UVM_LOW)
    end
`else
    `uvm_fatal("IBI_MULTI_RAL_BUILD",
               "Multi-Target IBI arbitration requires SMC_USE_I3C_RAL")
`endif
  endtask
endclass : smc_i3c_ibi_target_tx_multi_target_vseq

`endif // SMC_I3C_IBI_TARGET_TX_MULTI_TARGET_VSEQ_SV
