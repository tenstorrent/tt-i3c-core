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
// File        : smc_i3c_ibi_target_tx_dut_loss_vseq.sv
// Description : DUT-loss arbitration and retained-descriptor retry vseq.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-12
// *****************************************************************************

`ifndef SMC_I3C_IBI_TARGET_TX_DUT_LOSS_VSEQ_SV
`define SMC_I3C_IBI_TARGET_TX_DUT_LOSS_VSEQ_SV

class smc_i3c_ibi_target_tx_dut_loss_vseq extends smc_i3c_ibi_base_vseq;
  `uvm_object_utils(smc_i3c_ibi_target_tx_dut_loss_vseq)

  function new(string name = "smc_i3c_ibi_target_tx_dut_loss_vseq");
    super.new(name);
  endfunction

  protected task wait_done(ref bit done, input string operation);
    if (done)
      return;
    repeat (vseq_ctx.cfg.ibi_timeout_cycles) begin
      @(posedge vseq_ctx.cfg.vif.clk);
      if (done)
        return;
    end
    `uvm_fatal("IBI_DUT_LOSS_TIMEOUT", $sformatf("%s timed out", operation))
  endtask

  virtual task body();
    super.body();
    if (!vseq_ctx.cfg.has_rtl)
      `uvm_fatal("IBI_DUT_LOSS_MODE", "DUT-loss test requires DUT_MODE=rtl")
    if (vseq_ctx.cfg.ibi_dut_role != SMC_I3C_IBI_DUT_TARGET)
      `uvm_fatal("IBI_DUT_LOSS_ROLE", "DUT-loss vseq requires DUT-Target role")

`ifndef SMC_USE_I3C_RTL
    `uvm_fatal("IBI_DUT_LOSS_RTL_BUILD",
               "DUT-loss test requires SMC_USE_I3C_RTL")
`elsif SMC_USE_I3C_RAL
    begin
      smc_i3c_ral_model ral;
      smc_i3c_host_respond_ibi_burst_seq host_seq;
      smc_i3c_target_send_ibi_seq competitor_seq;
      smc_i3c_target_send_ibi_seq tertiary_seq;
      smc_i3c_target_send_ibi_seq quaternary_seq;
      smc_i3c_ibi_target_tx_busy_bus_block_vseq transfer_precursor;
      smc_i3c_host_busy_private_write_seq arbitration_private_seq;
      uvm_event host_armed_event;
      uvm_event host_detected_event;
      uvm_event competitor_armed_event;
      uvm_event tertiary_armed_event;
      uvm_event quaternary_armed_event;
      uvm_reg_data_t descriptor;
      uvm_reg_data_t status;
      bit host_done;
      bit competitor_done;
      bit tertiary_done;
      bit quaternary_done;
      bit status_done;
      bit [6:0] dut_addr;
      bit [6:0] competitor_addr;
      bit [6:0] tertiary_addr;
      bit [6:0] quaternary_addr;
      bit [7:0] dut_mdb;
      bit [7:0] competitor_mdb;
      int unsigned completion_before;
      int unsigned mismatch_before;
      int unsigned observed_attempt_before;
      int unsigned observed_retry_before;
      bit dut_wins;
      bit win_nack_retry;
      bit correlate_addr_arb;
      bit arbitrate_after_transfer;
      bit arbitration_private_done;
      int unsigned win_nack_retry_arg;
      int unsigned requester_count;
      int unsigned contested_requester_count;
      bit [1:0] contested_bus_state;
      bit [1:0] contested_arb_outcome;

      requester_count = vseq_ctx.cfg.ibi_requester_count;
      if ((requester_count < 2) || (requester_count > 4))
        `uvm_fatal("IBI_DUT_LOSS_REQUESTERS",
                   "DUT-loss requester count must be in [2:4]")
      if ((vseq_ctx.i3c_sqr == null) ||
          (vseq_ctx.i3c_target_sqr[1] == null) ||
          ((requester_count >= 3) &&
           (vseq_ctx.i3c_target_sqr[2] == null)) ||
          ((requester_count >= 4) &&
           (vseq_ctx.i3c_target_sqr[3] == null)))
        `uvm_fatal("IBI_DUT_LOSS_SQR",
                   "UVM Host and competing Target sequencers are required")
      if (!vseq_ctx.cfg.has_ibi_scoreboard)
        `uvm_fatal("IBI_DUT_LOSS_SCOREBOARD",
                   "DUT descriptor scoreboard is required")

      ral = get_i3c_ral_model();
      arbitrate_after_transfer =
        $test$plusargs("IBI_ARB_DURING_PRIVATE_WRITE");
      if (arbitrate_after_transfer &&
          $test$plusargs("IBI_ARB_PRECEDE_PRIVATE_WRITE"))
        `uvm_fatal("IBI_ARB_TRANSFER_MODE",
                   "Select either the sole-request precursor or contested-during-transfer mode, not both")
      if ($test$plusargs("IBI_ARB_PRECEDE_PRIVATE_WRITE")) begin
        // The precursor's deferred IBI is a sole-requester transaction. Keep
        // its ATTEMPT metadata independent from the later contested
        // transaction. The precursor itself publishes the after-transfer
        // attempt; arbitration starts only after that IBI has completed and
        // is therefore classified as bus-available, not after-transfer.
        contested_requester_count = vseq_ctx.cfg.ibi_requester_count;
        contested_bus_state = vseq_ctx.cfg.ibi_bus_state;
        contested_arb_outcome = vseq_ctx.cfg.ibi_arb_outcome;
        vseq_ctx.cfg.ibi_requester_count = 1;
        vseq_ctx.cfg.ibi_arb_outcome = 2'd0;
        `uvm_info("IBI_ARB_CONTEXT_PRECURSOR",
                  "Running checked Private Write before contested IBI arbitration",
                  UVM_LOW)
        transfer_precursor =
          smc_i3c_ibi_target_tx_busy_bus_block_vseq::type_id::create(
            "transfer_precursor");
        transfer_precursor.vseq_ctx = vseq_ctx;
        transfer_precursor.start(null);
        wait_bus_idle("confirm idle boundary after arbitration precursor");
        vseq_ctx.cfg.ibi_requester_count = contested_requester_count;
        vseq_ctx.cfg.ibi_bus_state = contested_bus_state;
        vseq_ctx.cfg.ibi_arb_outcome = contested_arb_outcome;
      end
      dut_addr = vseq_ctx.cfg.ibi_target_addr;
      competitor_addr = vseq_ctx.cfg.ibi_secondary_target_addr;
      tertiary_addr = vseq_ctx.cfg.ibi_target_addr_by_slot[2];
      quaternary_addr = vseq_ctx.cfg.ibi_target_addr_by_slot[3];
      dut_mdb = vseq_ctx.cfg.ibi_basic_mdb;
      competitor_mdb = dut_mdb ^ 8'h3c;
      dut_wins = vseq_ctx.cfg.ibi_dut_wins_arbitration;
      win_nack_retry_arg = 0;
      void'($value$plusargs("IBI_DUT_WIN_NACK_RETRY=%0d",
                            win_nack_retry_arg));
      win_nack_retry = (win_nack_retry_arg != 0);
      correlate_addr_arb = vseq_ctx.cfg.ibi_address_arb_status_correlation;
      if (win_nack_retry && !dut_wins)
        `uvm_fatal("IBI_DUT_WIN_NACK_MODE",
                   "IBI_DUT_WIN_NACK_RETRY requires the DUT-win test")
      if (correlate_addr_arb && dut_wins)
        `uvm_fatal("IBI_ADDR_ARB_CORRELATION_MODE",
                   "FailureAddressArb correlation requires the DUT-loss test")
      if ((!dut_wins && (competitor_addr >= dut_addr)) ||
          ( dut_wins && (competitor_addr <= dut_addr)))
        `uvm_fatal("IBI_ARB_ADDR_ORDER",
                   $sformatf("Competitor 0x%02h must be %s DUT 0x%02h",
                             competitor_addr,
                             dut_wins ? "above" : "below", dut_addr))

      completion_before = vseq_ctx.cfg.ibi_sb_completion_count;
      mismatch_before = vseq_ctx.cfg.ibi_sb_mismatch_count;
      observed_attempt_before = vseq_ctx.cfg.ibi_observed_attempt_count;
      observed_retry_before = vseq_ctx.cfg.ibi_observed_retry_count;
      vseq_ctx.cfg.ibi_expected_ack = 1'b1;
      vseq_ctx.cfg.ibi_expected_terminal_status = IBI_STATUS_SUCCESS;
      initialize_target_ibi(ral);
      // Keep one retry available for the loss case. In the win case the DUT
      // completes first and the higher-address UVM Target retries instead.
      write_field(ral.I3C_EC.TTI.CONTROL.IBI_RETRY_NUM, 1,
                  "allow one DUT retry after arbitration loss");
      write_field(ral.I3C_EC.TTI.INTERRUPT_ENABLE.IBI_DONE_EN, 1,
                  "enable DUT-loss IBI_DONE interrupt");
      clear_w1c_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 1,
                      "clear stale DUT-loss IBI_DONE");
      wait_irq(1'b0, "verify initial DUT-loss IRQ low");

      host_seq = smc_i3c_host_respond_ibi_burst_seq::type_id::create(
        "dut_loss_host_seq");
      if (win_nack_retry) begin
        // The first response belongs to a genuine contested attempt won by
        // the DUT.  NACK it, then ACK the retained descriptor on its retry.
        host_seq.rx_byte_count_q.push_back(0);
        host_seq.ibi_ack_q.push_back(1'b0);
        host_seq.rx_byte_count_q.push_back(1);
        host_seq.ibi_ack_q.push_back(1'b1);
      end else begin
        host_seq.rx_byte_count_q.push_back(1);
        host_seq.ibi_ack_q.push_back(1'b1);
        if (!dut_wins) begin
          host_seq.rx_byte_count_q.push_back(1);
          host_seq.ibi_ack_q.push_back(1'b1);
        end
      end
      competitor_seq = smc_i3c_target_send_ibi_seq::type_id::create(
        "lower_competitor_seq");
      competitor_seq.target_addr = competitor_addr;
      competitor_seq.mdb = competitor_mdb;
      // The DUT initiates START and the UVM Target joins the same address
      // arbitration. Address ordering selects a real DUT win or loss.
      competitor_seq.start_on_idle = 1'b0;
      if (requester_count >= 3) begin
        tertiary_seq = smc_i3c_target_send_ibi_seq::type_id::create(
          "tertiary_competitor_seq");
        tertiary_seq.target_addr = tertiary_addr;
        tertiary_seq.mdb = competitor_mdb ^ 8'h55;
        tertiary_seq.start_on_idle = 1'b0;
      end
      if (requester_count >= 4) begin
        quaternary_seq = smc_i3c_target_send_ibi_seq::type_id::create(
          "quaternary_competitor_seq");
        quaternary_seq.target_addr = quaternary_addr;
        quaternary_seq.mdb = competitor_mdb ^ 8'haa;
        quaternary_seq.start_on_idle = 1'b0;
      end
      descriptor = uvm_reg_data_t'(dut_mdb) << 24;
      host_armed_event = uvm_event_pool::get_global(
        SMC_I3C_HOST_IBI_ARMED_EVENT);
      host_detected_event = uvm_event_pool::get_global(
        SMC_I3C_HOST_IBI_DETECTED_EVENT);
      competitor_armed_event = uvm_event_pool::get_global(
        $sformatf("%s_1", SMC_I3C_TARGET_IBI_SLOT_ARMED_EVENT));
      tertiary_armed_event = uvm_event_pool::get_global(
        $sformatf("%s_2", SMC_I3C_TARGET_IBI_SLOT_ARMED_EVENT));
      quaternary_armed_event = uvm_event_pool::get_global(
        $sformatf("%s_3", SMC_I3C_TARGET_IBI_SLOT_ARMED_EVENT));
      host_armed_event.reset();
      host_detected_event.reset();
      competitor_armed_event.reset();
      tertiary_armed_event.reset();
      quaternary_armed_event.reset();
      host_done = 1'b0;
      competitor_done = 1'b0;
      tertiary_done = (requester_count < 3);
      quaternary_done = (requester_count < 4);
      status_done = !(win_nack_retry || correlate_addr_arb);

      arbitration_private_done = !arbitrate_after_transfer;
      if (arbitrate_after_transfer) begin
        // Arm every external requester while idle, but hold the target
        // drivers behind their existing arbitration barrier. This permits a
        // normal Controller transfer to own the bus without losing the
        // pending requests or allowing the VIP to inject an early START.
        vseq_ctx.cfg.ibi_target_driver_barrier_enable = 1'b1;
        vseq_ctx.cfg.ibi_target_driver_release = 1'b0;
        fork : prearmed_after_transfer_competitors
          begin
            competitor_seq.start(vseq_ctx.i3c_target_sqr[1]);
            competitor_done = 1'b1;
          end
          begin
            if (requester_count >= 3) begin
              tertiary_seq.start(vseq_ctx.i3c_target_sqr[2]);
              tertiary_done = 1'b1;
            end
          end
          begin
            if (requester_count >= 4) begin
              quaternary_seq.start(vseq_ctx.i3c_target_sqr[3]);
              quaternary_done = 1'b1;
            end
          end
        join_none
        competitor_armed_event.wait_on();
        if (requester_count >= 3)
          tertiary_armed_event.wait_on();
        if (requester_count >= 4)
          quaternary_armed_event.wait_on();

        arbitration_private_seq =
          smc_i3c_host_busy_private_write_seq::type_id::create(
            "arbitration_private_seq");
        arbitration_private_seq.target_addr = dut_addr;
        for (int unsigned index = 0; index < 16; index++)
          arbitration_private_seq.tx_data.push_back(8'h80 + index[7:0]);
        vseq_ctx.cfg.vif.i3c_timing_normal_active = 1'b1;
        vseq_ctx.cfg.vif.i3c_timing_ibi_pending = 1'b0;
        fork : arbitration_private_transfer
          begin
            arbitration_private_seq.start(vseq_ctx.i3c_sqr);
            arbitration_private_done = 1'b1;
            vseq_ctx.cfg.vif.i3c_timing_normal_active = 1'b0;
            // Release all pre-armed Targets only after the normal transfer
            // has emitted STOP. They then join the DUT at its first legal
            // post-transfer IBI address-arbitration window.
            vseq_ctx.cfg.ibi_target_driver_release = 1'b1;
          end
        join_none
        for (int unsigned cycle = 0;
             cycle < vseq_ctx.cfg.ibi_timeout_cycles; cycle++) begin
          if (arbitration_private_seq.address_acked &&
              (vseq_ctx.cfg.i3c_vif.host_sda_pp_en === 1'b1) &&
              (vseq_ctx.cfg.i3c_vif.scl_pp_en === 1'b1))
            break;
          if (cycle == (vseq_ctx.cfg.ibi_timeout_cycles - 1))
            `uvm_fatal("IBI_ARB_PRIVATE_TIMEOUT",
                       "Private Write did not enter its active data phase")
          @(posedge vseq_ctx.cfg.vif.clk);
        end
        vseq_ctx.cfg.ibi_bus_state = 2'd2;
        vseq_ctx.cfg.ibi_requester_count = requester_count;
        vseq_ctx.cfg.ibi_arb_outcome = dut_wins ? 2'd1 : 2'd2;
        vseq_ctx.cfg.vif.i3c_timing_ibi_pending = 1'b1;
        write_register(ral.I3C_EC.TTI.IBI_PORT, descriptor,
                       "queue contested DUT descriptor during active Private Write");
      end

      fork : dut_loss_transaction
        begin
          // host_seq shares the Controller sequencer with the optional
          // arbitration_private_seq. The VIP driver accepts one item at a
          // time and does not prefetch: this IBI responder request remains
          // queued until the Private Write item, including its physical
          // STOP, has completed and returned its response.
          host_seq.start(vseq_ctx.i3c_sqr);
          host_done = 1'b1;
        end
        begin
          if (!arbitrate_after_transfer) begin
            competitor_seq.start(vseq_ctx.i3c_target_sqr[1]);
            competitor_done = 1'b1;
          end
        end
        begin
          if (!arbitrate_after_transfer && (requester_count >= 3)) begin
            tertiary_seq.start(vseq_ctx.i3c_target_sqr[2]);
            tertiary_done = 1'b1;
          end
        end
        begin
          if (!arbitrate_after_transfer && (requester_count >= 4)) begin
            quaternary_seq.start(vseq_ctx.i3c_target_sqr[3]);
            quaternary_done = 1'b1;
          end
        end
        begin
          // In the post-transfer case the Controller sequencer is occupied
          // by the Private Write. Queue the DUT request after all competing
          // Targets are armed; the Host responder is dispatched immediately
          // after the Private Write and before the programmed T_AVAL expires.
          if (!arbitrate_after_transfer) begin
            host_armed_event.wait_on();
            host_armed_event.reset();
            competitor_armed_event.wait_on();
            if (requester_count >= 3)
              tertiary_armed_event.wait_on();
            if (requester_count >= 4)
              quaternary_armed_event.wait_on();
            vseq_ctx.cfg.ibi_requester_count = requester_count;
            vseq_ctx.cfg.ibi_arb_outcome = dut_wins ? 2'd1 : 2'd2;
            write_register(ral.I3C_EC.TTI.IBI_PORT, descriptor,
                           "queue DUT descriptor against lower Target");
          end
        end
        begin
          uvm_reg_data_t attempt_status;
          if (win_nack_retry) begin
            host_detected_event.wait_on();
            host_detected_event.reset();
            if (arbitrate_after_transfer) begin
              // As in the correlated-loss path, consume the persistent ARMED
              // state belonging to the first post-transfer response. The
              // later wait must synchronize with the burst sequence's second
              // request before the retained DUT descriptor is released.
              host_armed_event.reset();
            end
            write_field(ral.I3C_EC.TTI.CONTROL.IBI_EN, 0,
                        "pause retry after contested winner NACK");
            wait_field_value(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 1,
                             "wait for contested winner NACK status");
            read_field(ral.I3C_EC.TTI.STATUS.LAST_IBI_STATUS,
                       attempt_status,
                       "capture contested winner NACK status");
            if (attempt_status != uvm_reg_data_t'(IBI_STATUS_FAILURE_NACK))
              `uvm_fatal("IBI_DUT_WIN_NACK_STATUS",
                         $sformatf("Expected FAILURE_NACK, got 0x%0h",
                                   attempt_status))
            wait_irq(1'b0, "clear contested winner NACK IRQ");
            wait_bus_idle("wait idle after contested winner NACK");
            host_armed_event.wait_on();
            host_armed_event.reset();
            write_field(ral.I3C_EC.TTI.CONTROL.IBI_EN, 1,
                        "release retained descriptor retry");
            host_detected_event.wait_on();
            host_detected_event.reset();
            wait_field_value(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 1,
                             "wait for retained descriptor success");
            read_field(ral.I3C_EC.TTI.STATUS.LAST_IBI_STATUS,
                       attempt_status,
                       "capture retained descriptor success");
            if (attempt_status != uvm_reg_data_t'(IBI_STATUS_SUCCESS))
              `uvm_fatal("IBI_DUT_WIN_RETRY_STATUS",
                         $sformatf("Expected SUCCESS, got 0x%0h",
                                   attempt_status))
            wait_irq(1'b0, "clear retained descriptor success IRQ");
            status_done = 1'b1;
          end else if (correlate_addr_arb) begin
            // The lower-address external Target is the only Host-visible
            // winner. Pause the DUT retry after that winner is detected so
            // FAILURE_ADDRESS_ARB can be read before a retry overwrites the
            // shared LAST_IBI_STATUS field.
            host_detected_event.wait_on();
            host_detected_event.reset();
            if (arbitrate_after_transfer) begin
              // The post-transfer path does not consume the first ARMED event
              // before queuing the DUT descriptor because the Controller
              // sequencer is still executing the Private Write. Detection of
              // the first IBI proves that request was dispatched; clear its
              // persistent event state now so the wait below observes only
              // the burst sequence's second (DUT-retry) response request.
              host_armed_event.reset();
            end
            write_field(ral.I3C_EC.TTI.CONTROL.IBI_EN, 0,
                        "pause retained descriptor after address arbitration loss");
            wait_field_value(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 1,
                             "correlate address-arbitration-loss IBI_DONE");
            read_field(ral.I3C_EC.TTI.STATUS.LAST_IBI_STATUS,
                       attempt_status,
                       "correlate address-arbitration-loss LAST_IBI_STATUS");
            if (attempt_status !=
                uvm_reg_data_t'(IBI_STATUS_FAILURE_ADDRESS_ARB))
              `uvm_fatal(
                "IBI_FAILURE_ADDR_ARB_STATUS",
                $sformatf("Expected FAILURE_ADDRESS_ARB (0x%0h), got 0x%0h",
                          IBI_STATUS_FAILURE_ADDRESS_ARB, attempt_status))
            `uvm_info(
              "IBI_FAILURE_ADDR_ARB_CHECK",
              $sformatf("DUT descriptor DA=0x%02h: IBI_DONE=1 and LAST_IBI_STATUS=0x%0h confirmed before retry",
                        dut_addr, attempt_status),
              UVM_LOW)
            wait_irq(1'b0, "clear address-arbitration-loss IRQ");
            wait_bus_idle("wait idle after external arbitration winner");
            host_armed_event.wait_on();
            host_armed_event.reset();
            write_field(ral.I3C_EC.TTI.CONTROL.IBI_EN, 1,
                        "release retained descriptor after status correlation");
            status_done = 1'b1;
          end
        end
      join_none
      wait_done(competitor_done, "competing Target arbitration result");
      wait_done(tertiary_done, "tertiary Target arbitration result");
      wait_done(quaternary_done, "quaternary Target arbitration result");
      wait_done(host_done, dut_wins ? "DUT arbitration winner transfer" :
                                     "lower Target winner plus DUT retry");
      wait_done(status_done, "DUT intermediate status capture");
      wait_done(arbitration_private_done,
                "Private Write preceding contested IBI arbitration");
      disable dut_loss_transaction;

      if (arbitrate_after_transfer &&
          (!arbitration_private_seq.address_acked ||
           !arbitration_private_seq.transfer_done))
        `uvm_fatal("IBI_ARB_PRIVATE_RESULT",
                   "Private Write did not complete before contested IBI arbitration")

      if (!competitor_seq.response_valid ||
          (competitor_seq.observed_ack != !dut_wins))
        `uvm_fatal("IBI_ARB_COMPETITOR",
                   $sformatf("Competing UVM Target ACK=%0b, expected %0b",
                             competitor_seq.observed_ack, !dut_wins))
      if ((requester_count >= 3) &&
          (!tertiary_seq.response_valid || tertiary_seq.observed_ack))
        `uvm_fatal("IBI_ARB_TERTIARY",
                   "Tertiary competitor did not lose/release cleanly")
      if ((requester_count >= 4) &&
          (!quaternary_seq.response_valid || quaternary_seq.observed_ack))
        `uvm_fatal("IBI_ARB_QUATERNARY",
                   "Quaternary competitor did not lose/release cleanly")
      if (host_seq.response_count != ((win_nack_retry || !dut_wins) ? 2 : 1))
        `uvm_fatal("IBI_DUT_LOSS_HOST_COUNT",
                   $sformatf("Expected %0d host IBI response(s), got %0d",
                             (win_nack_retry || !dut_wins) ? 2 : 1,
                             host_seq.response_count))
      if (dut_wins) begin
        if (host_seq.response_addr_q[0] != dut_addr)
          `uvm_fatal("IBI_ARB_RESPONSE_ORDER",
                     $sformatf("Expected DUT winner 0x%02h, got 0x%02h",
                               dut_addr, host_seq.response_addr_q[0]))
      end else if ((host_seq.response_addr_q[0] != competitor_addr) ||
                   (host_seq.response_addr_q[1] != dut_addr)) begin
        `uvm_fatal("IBI_ARB_RESPONSE_ORDER",
                   $sformatf("Expected winner/retry order 0x%02h/0x%02h, got 0x%02h/0x%02h",
                             competitor_addr, dut_addr,
                             host_seq.response_addr_q[0],
                             host_seq.response_addr_q[1]))
      end

      if (!win_nack_retry) begin
        wait_irq(1'b1, "wait for retained DUT descriptor completion IRQ");
        expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 1,
                     "confirm retained DUT descriptor IBI_DONE source");
        read_field(ral.I3C_EC.TTI.STATUS.LAST_IBI_STATUS, status,
                   "read retained DUT descriptor terminal status");
        if (status != uvm_reg_data_t'(IBI_STATUS_SUCCESS))
          `uvm_fatal("IBI_DUT_LOSS_STATUS",
                     $sformatf("Retried DUT descriptor expected SUCCESS, got 0x%0h",
                               status))
        wait_irq(1'b0, "wait for retained DUT descriptor IRQ clear");
      end
      wait_scoreboard_completion(completion_before + 1,
                                 "wait for retained DUT descriptor match");
      if (vseq_ctx.cfg.ibi_sb_mismatch_count != mismatch_before)
        `uvm_fatal("IBI_DUT_LOSS_SCOREBOARD",
                   "DUT-loss/retry added a descriptor mismatch")
      if (correlate_addr_arb &&
          ((vseq_ctx.cfg.ibi_observed_attempt_count -
            observed_attempt_before) != 2))
        `uvm_fatal(
          "IBI_FAILURE_ADDR_ARB_ATTEMPTS",
          $sformatf("Expected correlated loss plus successful retry (2 attempts), observed %0d",
                    vseq_ctx.cfg.ibi_observed_attempt_count -
                    observed_attempt_before))
      if (correlate_addr_arb &&
          ((vseq_ctx.cfg.ibi_observed_retry_count -
            observed_retry_before) != 1))
        `uvm_fatal(
          "IBI_FAILURE_ADDR_ARB_RETRY",
          $sformatf("Expected one correlated address-arbitration retry, observed %0d",
                    vseq_ctx.cfg.ibi_observed_retry_count -
                    observed_retry_before))
      wait_bus_idle("check idle bus after DUT-loss retry");
      if (arbitrate_after_transfer) begin
        vseq_ctx.cfg.vif.i3c_timing_ibi_pending = 1'b0;
        vseq_ctx.cfg.ibi_bus_state = 2'd0;
        vseq_ctx.cfg.ibi_target_driver_barrier_enable = 1'b0;
        vseq_ctx.cfg.ibi_target_driver_release = 1'b0;
      end

      `uvm_info("IBI_DUT_LOSS_PASS",
        $sformatf("DUT Target 0x%02h %s arbitration against UVM Target 0x%02h; winner transfer completed",
                          dut_addr, dut_wins ? "won" : "lost",
                          competitor_addr),
                UVM_LOW)
    end
`else
    `uvm_fatal("IBI_DUT_LOSS_RAL_BUILD",
               "DUT-loss test requires SMC_USE_I3C_RAL")
`endif
  endtask
endclass : smc_i3c_ibi_target_tx_dut_loss_vseq

`endif
