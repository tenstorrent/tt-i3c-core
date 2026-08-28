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
// File        : smc_i3c_ibi_target_tx_busy_bus_block_vseq.sv
// Description : Target-TX IBI exclusion during an active private transfer.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-06
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_TARGET_TX_BUSY_BUS_BLOCK_VSEQ_SV
`define SMC_I3C_IBI_TARGET_TX_BUSY_BUS_BLOCK_VSEQ_SV

// A Controller-owned Private Write long enough for the virtual sequence to
// queue a Target IBI while push-pull data is actively crossing the bus.
`ifdef SMC_USE_I3C_RTL
class smc_i3c_host_busy_private_write_seq extends
    uvm_sequence #(i3c_seq_item, i3c_seq_item);
  `uvm_object_utils(smc_i3c_host_busy_private_write_seq)

  bit [6:0] target_addr;
  byte unsigned tx_data[$];
  bit address_acked;
  bit transfer_done;

  function new(string name = "smc_i3c_host_busy_private_write_seq");
    super.new(name);
  endfunction

  virtual task body();
    i3c_seq_item address_response;
    i3c_seq_item transfer_response;

    address_acked = 1'b0;
    transfer_done = 1'b0;
    if (tx_data.size() == 0)
      `uvm_fatal("IBI_BUSY_WRITE_CFG",
                 "Busy-bus Private Write requires at least one data byte")

    req = i3c_seq_item::type_id::create("address_req");
    start_item(req);
    req.i3c = 1'b1;
    req.addr = target_addr;
    req.dir = 1'b0;
    req.dev_ack = 1'b1;
    req.end_with_rstart = 1'b0;
    req.is_daa = 1'b0;
    req.data.delete();
    req.data_cnt = 0;
    req.T_bit.delete();
    req.IBI = 1'b0;
    req.IBI_ADDR = '0;
    req.IBI_START = 1'b0;
    req.IBI_ACK = 1'b0;
    finish_item(req);
    get_response(address_response);
    if (address_response == null)
      `uvm_fatal("IBI_BUSY_ADDRESS_RSP",
                 "Controller BFM returned no Private Write address response")
    if (!address_response.dev_ack)
      `uvm_fatal("IBI_BUSY_ADDRESS_NACK",
                 $sformatf("DUT Target NACKed Private Write DA=0x%02h",
                           target_addr))
    address_acked = 1'b1;

    req = i3c_seq_item::type_id::create("transfer_req");
    start_item(req);
    req.i3c = 1'b1;
    req.addr = target_addr;
    req.dir = 1'b0;
    req.dev_ack = 1'b1;
    req.end_with_rstart = 1'b0;
    req.is_daa = 1'b0;
    req.data.delete();
    req.T_bit.delete();
    foreach (tx_data[index]) begin
      req.data.push_back(tx_data[index]);
      // Controller Write Data uses the odd-parity T-bit encoding expected by
      // this VIP and by the DUT Target receiver.
      req.T_bit.push_back(!(^tx_data[index]));
    end
    req.data_cnt = tx_data.size();
    req.IBI = 1'b0;
    req.IBI_ADDR = '0;
    req.IBI_START = 1'b0;
    req.IBI_ACK = 1'b0;
    finish_item(req);
    get_response(transfer_response);
    if (transfer_response == null)
      `uvm_fatal("IBI_BUSY_TRANSFER_RSP",
                 "Controller BFM returned no Private Write transfer response")
    transfer_done = 1'b1;
  endtask
endclass : smc_i3c_host_busy_private_write_seq
`endif

class smc_i3c_ibi_target_tx_busy_bus_block_vseq extends smc_i3c_ibi_base_vseq;
  `uvm_object_utils(smc_i3c_ibi_target_tx_busy_bus_block_vseq)

  localparam int unsigned PRIVATE_WRITE_BYTES = 16;

  function new(string name = "smc_i3c_ibi_target_tx_busy_bus_block_vseq");
    super.new(name);
  endfunction

`ifdef SMC_USE_I3C_RTL
`ifdef SMC_USE_I3C_RAL
  protected task wait_private_data_phase(input string operation);
    for (int unsigned cycle = 0;
         cycle < vseq_ctx.cfg.ibi_timeout_cycles; cycle++) begin
      if ((vseq_ctx.cfg.i3c_vif.host_sda_pp_en === 1'b1) &&
          (vseq_ctx.cfg.i3c_vif.scl_pp_en === 1'b1))
        return;
      @(posedge vseq_ctx.cfg.vif.clk);
    end
    `uvm_fatal("IBI_BUSY_DATA_TIMEOUT",
               $sformatf("%s: Controller never entered push-pull data phase",
                         operation))
  endtask

  protected task wait_private_address_ack(
      input smc_i3c_host_busy_private_write_seq private_seq,
      input string operation);
    for (int unsigned cycle = 0;
         cycle < vseq_ctx.cfg.ibi_timeout_cycles; cycle++) begin
      if (private_seq.address_acked)
        return;
      @(posedge vseq_ctx.cfg.vif.clk);
    end
    `uvm_fatal("IBI_BUSY_ADDRESS_TIMEOUT",
               $sformatf("%s: Private Write address phase did not ACK",
                         operation))
  endtask

  protected task capture_stop_to_ibi_start(
      input uvm_reg_data_t t_aval,
      output int unsigned available_cycles,
      output realtime available_time,
      output bit timing_complete);
    bit stop_seen;
    bit start_seen;
    realtime stop_timestamp;

    available_cycles = 0;
    available_time = 0.0;
    timing_complete = 1'b0;
    stop_seen = 1'b0;
    start_seen = 1'b0;

    fork : stop_to_start_timeout_guard
      begin
        // During compliant SDR data, SDA changes while SCL is low. The first
        // SDA rising edge sampled with SCL high is therefore the Private Write
        // STOP that begins the Target's Bus Available interval.
        do begin
          @(posedge vseq_ctx.cfg.i3c_vif.sda_i);
        end while (vseq_ctx.cfg.i3c_vif.scl_i !== 1'b1);
        stop_seen = 1'b1;
        stop_timestamp = $realtime;

        fork : available_counter
          begin
            while (!start_seen) begin
              @(posedge vseq_ctx.cfg.vif.clk);
              if (!start_seen)
                available_cycles++;
            end
          end
          begin
            do begin
              @(negedge vseq_ctx.cfg.i3c_vif.sda_i);
            end while (vseq_ctx.cfg.i3c_vif.scl_i !== 1'b1);
            if (vseq_ctx.cfg.vif.i3c_sda_oe !== 1'b1)
              `uvm_fatal("IBI_BUSY_START_OWNER",
                         "Deferred START was not initiated by the DUT Target")
            if ((vseq_ctx.cfg.i3c_vif.host_sda_o !== 1'b1) ||
                (vseq_ctx.cfg.i3c_vif.host_sda_pp_en !== 1'b0))
              `uvm_fatal("IBI_BUSY_START_CONTENTION",
                         "UVM Controller drove SDA at the deferred Target START edge")
            available_time = $realtime - stop_timestamp;
            start_seen = 1'b1;
          end
        join_any
        disable available_counter;

        if (available_cycles < int'(t_aval))
          `uvm_fatal("IBI_BUSY_T_AVAL",
                     $sformatf("Target IBI START occurred %0d core clocks after STOP, below programmed T_AVAL=%0d",
                               available_cycles, t_aval))
        timing_complete = 1'b1;
      end
      begin
        repeat (vseq_ctx.cfg.ibi_timeout_cycles)
          @(posedge vseq_ctx.cfg.vif.clk);
        if (!timing_complete)
          `uvm_fatal("IBI_BUSY_RETRY_TIMEOUT",
                     $sformatf("STOP/start timing did not complete: stop=%0b start=%0b",
                               stop_seen, start_seen))
      end
    join_any
    disable stop_to_start_timeout_guard;
  endtask

  protected task check_private_write_queues(input smc_i3c_ral_model ral,
                                            input byte unsigned expected[$]);
    uvm_reg_data_t descriptor;
    uvm_reg_data_t data_word;
    int unsigned expected_words;

    expected_words = (expected.size() + 3) / 4;
    wait_field_value(ral.I3C_EC.TTI.DESC_QUEUE_DEPTH.RX_DESC_QUEUE_DEPTH,
                     1, "wait for busy-bus Private Write RX descriptor");
    wait_field_value(ral.I3C_EC.TTI.DATA_QUEUE_DEPTH.RX_DATA_QUEUE_DEPTH,
                     expected_words,
                     "wait for busy-bus Private Write RX data");

    read_field(ral.I3C_EC.TTI.RX_DESC_QUEUE_PORT.RX_DESC, descriptor,
               "read busy-bus Private Write RX descriptor");
    if ((descriptor[31:28] != 4'h0) ||
        (descriptor[15:0] != expected.size()))
      `uvm_fatal("IBI_BUSY_RX_DESCRIPTOR",
                 $sformatf("Private Write descriptor expected error=0 length=%0d, actual=0x%08h",
                           expected.size(), descriptor))

    for (int unsigned word_index = 0;
         word_index < expected_words; word_index++) begin
      read_field(ral.I3C_EC.TTI.RX_DATA_PORT.RX_DATA, data_word,
                 $sformatf("read busy-bus Private Write RX word %0d",
                           word_index));
      for (int unsigned lane = 0; lane < 4; lane++) begin
        int unsigned byte_index;

        byte_index = (word_index * 4) + lane;
        if ((byte_index < expected.size()) &&
            (data_word[8*lane +: 8] != expected[byte_index]))
          `uvm_fatal("IBI_BUSY_RX_DATA",
                     $sformatf("Private Write byte[%0d] expected=0x%02h actual=0x%02h (word=0x%08h)",
                               byte_index, expected[byte_index],
                               data_word[8*lane +: 8], data_word))
      end
    end
  endtask
`endif
`endif

  virtual task body();
    super.body();
    if (!vseq_ctx.cfg.has_rtl)
      `uvm_fatal("IBI_BUSY_MODE",
                 "smc_i3c_ibi_target_tx_busy_bus_block_test requires DUT_MODE=rtl")
    if (vseq_ctx.cfg.ibi_dut_role != SMC_I3C_IBI_DUT_TARGET)
      `uvm_fatal("IBI_BUSY_ROLE",
                 "smc_i3c_ibi_target_tx_busy_bus_block_test requires DUT-target/UVM-controller role")

`ifdef SMC_USE_I3C_RTL
`ifdef SMC_USE_I3C_RAL
    begin
      smc_i3c_ral_model ral;
      smc_i3c_host_busy_private_write_seq private_seq;
      smc_i3c_host_accept_ibi_seq host_seq;
      uvm_reg_data_t descriptor;
      uvm_reg_data_t field_value;
      uvm_reg_data_t t_aval;
      byte unsigned expected_write[$];
      int unsigned completion_before;
      int unsigned mismatch_before;
      int unsigned available_cycles;
      int unsigned ibi_stop_count;
      bit private_done;
      bit host_done;
      bit target_drove_during_transfer;
      bit timing_complete;
      bit ibi_start_seen;
      bit stop_count_complete;
      realtime available_time;

      if (vseq_ctx.i3c_sqr == null)
        `uvm_fatal("IBI_BUSY_SQR",
                   "I3C UVM Controller sequencer is not available")
      if (!vseq_ctx.cfg.has_ibi_scoreboard)
        `uvm_fatal("IBI_BUSY_SCOREBOARD",
                   "Busy-bus retry test requires the Target-TX scoreboard")

      ral = get_i3c_ral_model();
      initialize_target_ibi(ral);
      write_field(ral.I3C_EC.TTI.INTERRUPT_ENABLE.IBI_DONE_EN, 1,
                  "enable busy-bus IBI completion interrupt");
      read_field(ral.I3C_EC.SoCMgmtIf.T_AVAL_REG.T_AVAL, t_aval,
                 "read programmed Target Bus Available interval");
      if (t_aval == 0)
        `uvm_fatal("IBI_BUSY_T_AVAL_CFG",
                   "T_AVAL must be non-zero for the busy-bus exclusion test")

      private_seq = smc_i3c_host_busy_private_write_seq::type_id::create(
        "private_write_seq");
      private_seq.target_addr = vseq_ctx.cfg.ibi_target_addr;
      for (int unsigned index = 0; index < PRIVATE_WRITE_BYTES; index++) begin
        byte unsigned value;

        value = 8'h40 + index[7:0];
        expected_write.push_back(value);
        private_seq.tx_data.push_back(value);
      end

      host_seq = smc_i3c_host_accept_ibi_seq::type_id::create("host_ibi_seq");
      completion_before = vseq_ctx.cfg.ibi_sb_completion_count;
      mismatch_before = vseq_ctx.cfg.ibi_sb_mismatch_count;
      vseq_ctx.cfg.ibi_expected_ack = 1'b1;
      vseq_ctx.cfg.ibi_expected_terminal_status = IBI_STATUS_SUCCESS;
      descriptor = uvm_reg_data_t'(vseq_ctx.cfg.ibi_basic_mdb) << 24;
      private_done = 1'b0;
      host_done = 1'b0;
      target_drove_during_transfer = 1'b0;
      timing_complete = 1'b0;
      ibi_start_seen = 1'b0;
      stop_count_complete = 1'b0;
      ibi_stop_count = 0;
      vseq_ctx.cfg.vif.i3c_timing_normal_active = 1'b1;
      vseq_ctx.cfg.vif.i3c_timing_ibi_pending = 1'b0;

      fork : busy_bus_activity
        begin
          private_seq.start(vseq_ctx.i3c_sqr);
          private_done = 1'b1;
        end
      join_none

      // host_sda_pp_en is also asserted for the address bits. First require
      // the address ACK response, then wait for the second item's push-pull
      // phase so the IBI is unquestionably queued during Write Data.
      wait_private_address_ack(private_seq,
                               "wait for Private Write address ACK");
      wait_private_data_phase("wait for active Private Write data");
      if (vseq_ctx.cfg.vif.i3c_sda_oe !== 1'b0)
        `uvm_fatal("IBI_BUSY_PREEXISTING_DRIVE",
                   "DUT Target still owned SDA at Private Write data entry")

      fork : busy_bus_observers
        capture_stop_to_ibi_start(t_aval, available_cycles, available_time,
                                  timing_complete);
        begin
          host_seq.start(vseq_ctx.i3c_sqr);
          host_done = 1'b1;
        end
        begin
          while (!private_done) begin
            @(posedge vseq_ctx.cfg.vif.clk);
            if (vseq_ctx.cfg.vif.i3c_sda_oe === 1'b1)
              target_drove_during_transfer = 1'b1;
          end
        end
        begin
          // Count physical STOP conditions from the deferred Target START
          // through completion. The old Controller handoff produced an early
          // Target-release STOP plus the intended Controller STOP.
          do begin
            @(negedge vseq_ctx.cfg.i3c_vif.sda_i);
          end while (vseq_ctx.cfg.i3c_vif.scl_i !== 1'b1);
          ibi_start_seen = 1'b1;
          fork : ibi_stop_counter
            begin
              forever begin
                @(posedge vseq_ctx.cfg.i3c_vif.sda_i);
                if (vseq_ctx.cfg.i3c_vif.scl_i === 1'b1)
                  ibi_stop_count++;
              end
            end
            begin
              wait (host_done);
              stop_count_complete = 1'b1;
            end
          join_any
          disable ibi_stop_counter;
        end
      join_none

      // This AXI write occurs while the Controller owns an active push-pull
      // transfer. A compliant Target retains it without injecting a START or
      // driving SDA until the transfer ends and Bus Available is reached.
      vseq_ctx.cfg.vif.i3c_timing_ibi_pending = 1'b1;
      // The ATTEMPT event is published only when the deferred request starts.
      // Classify that accepted request as post-transfer evidence rather than
      // as an ordinary idle request.
      vseq_ctx.cfg.ibi_bus_state = 2'd2;
      write_register(ral.I3C_EC.TTI.IBI_PORT, descriptor,
                     "queue Target IBI during active Private Write");

      for (int unsigned cycle = 0;
           cycle < vseq_ctx.cfg.ibi_timeout_cycles; cycle++) begin
        if (private_done)
          break;
        if (cycle == (vseq_ctx.cfg.ibi_timeout_cycles - 1))
          `uvm_fatal("IBI_BUSY_PRIVATE_TIMEOUT",
                     "Private Write did not complete after queuing IBI")
        @(posedge vseq_ctx.cfg.vif.clk);
      end
      if (!private_seq.address_acked || !private_seq.transfer_done)
        `uvm_fatal("IBI_BUSY_PRIVATE_RESULT",
                   $sformatf("Private Write incomplete: address_ack=%0b transfer_done=%0b",
                             private_seq.address_acked,
                             private_seq.transfer_done))
      vseq_ctx.cfg.vif.i3c_timing_normal_active = 1'b0;
      if (target_drove_during_transfer)
        `uvm_fatal("IBI_BUSY_INJECTION",
                   "DUT Target enabled SDA while Controller owned the active Private Write")

      check_private_write_queues(ral, expected_write);

      for (int unsigned cycle = 0;
           cycle < vseq_ctx.cfg.ibi_timeout_cycles; cycle++) begin
        if (host_done && timing_complete && stop_count_complete)
          break;
        if (cycle == (vseq_ctx.cfg.ibi_timeout_cycles - 1))
          `uvm_fatal("IBI_BUSY_HOST_TIMEOUT",
                     $sformatf("Deferred IBI incomplete: host=%0b timing=%0b stop_count=%0b",
                               host_done, timing_complete,
                               stop_count_complete))
        @(posedge vseq_ctx.cfg.vif.clk);
      end
      disable busy_bus_observers;
      disable busy_bus_activity;

      if (!ibi_start_seen || (ibi_stop_count != 1))
        `uvm_fatal("IBI_BUSY_STOP_COUNT",
                   $sformatf("Deferred IBI expected one physical STOP after START, observed start=%0b stops=%0d",
                             ibi_start_seen, ibi_stop_count))

      if (!host_seq.response_valid ||
          (host_seq.response_addr != vseq_ctx.cfg.ibi_target_addr) ||
          (host_seq.response_data.size() != 1) ||
          (host_seq.response_data[0] != vseq_ctx.cfg.ibi_basic_mdb))
        `uvm_fatal("IBI_BUSY_HOST_RESULT",
                   $sformatf("Deferred IBI response invalid: valid=%0b DA=0x%02h bytes=%0d MDB=0x%02h",
                             host_seq.response_valid,
                             host_seq.response_addr,
                             host_seq.response_data.size(),
                             (host_seq.response_data.size() == 0) ?
                               8'h00 : host_seq.response_data[0]))

      wait_irq(1'b1, "wait for deferred busy-bus IBI completion IRQ");
      expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 1,
                   "confirm deferred busy-bus IBI_DONE");
      read_field(ral.I3C_EC.TTI.STATUS.LAST_IBI_STATUS, field_value,
                 "read deferred busy-bus LAST_IBI_STATUS");
      if (field_value != uvm_reg_data_t'(IBI_STATUS_SUCCESS))
        `uvm_fatal("IBI_BUSY_TERMINAL_STATUS",
                   $sformatf("Deferred IBI expected SUCCESS, actual=0x%0h",
                             field_value))
      wait_irq(1'b0, "wait for deferred IBI IRQ clear");
      wait_scoreboard_completion(completion_before + 1,
                                 "wait for deferred IBI scoreboard result");
      if (vseq_ctx.cfg.ibi_sb_mismatch_count != mismatch_before)
        `uvm_fatal("IBI_BUSY_SCOREBOARD_RESULT",
                   $sformatf("Busy-bus IBI added %0d scoreboard mismatch(es)",
                             vseq_ctx.cfg.ibi_sb_mismatch_count -
                             mismatch_before))
      expect_field(ral.I3C_EC.TTI.IBI_QUEUE_DEPTH.IBI_QUEUE_DEPTH, 0,
                   "confirm deferred IBI request was consumed once");
      wait_bus_idle("check bus idle after deferred busy-bus IBI");
      vseq_ctx.cfg.vif.i3c_timing_ibi_pending = 1'b0;
      vseq_ctx.cfg.ibi_bus_state = 2'd0;

      if (vseq_ctx.i3c_ibi_blocked_cov != null)
        vseq_ctx.i3c_ibi_blocked_cov.sample_blocked(
          1'b0, 1'b1, !target_drove_during_transfer,
          private_seq.address_acked && private_seq.transfer_done,
          timing_complete, ibi_start_seen && (available_cycles >= t_aval));

      `uvm_info("IBI_BUSY_BUS_BLOCK",
                $sformatf("PASS: %0d-byte Private Write was uncorrupted; Target did not inject IBI while busy and retried after %.3f ns (%0d core clocks, T_AVAL=%0d clocks); one physical IBI STOP observed",
                          PRIVATE_WRITE_BYTES, available_time,
                          available_cycles, t_aval),
                UVM_LOW)
    end
`else
    `uvm_fatal("IBI_BUSY_RAL_BUILD",
               "smc_i3c_ibi_target_tx_busy_bus_block_test requires SMC_USE_I3C_RAL")
`endif
`else
    `uvm_fatal("IBI_BUSY_RTL_BUILD",
               "smc_i3c_ibi_target_tx_busy_bus_block_test requires SMC_USE_I3C_RTL")
`endif
  endtask
endclass : smc_i3c_ibi_target_tx_busy_bus_block_vseq

`endif // SMC_I3C_IBI_TARGET_TX_BUSY_BUS_BLOCK_VSEQ_SV
