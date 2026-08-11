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
// File        : smc_i3c_ibi_controller_timing_context_vseq.sv
// Description : Virtual sequence for I3C IBI controller timing context.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-28
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_CONTROLLER_TIMING_CONTEXT_VSEQ_SV
`define SMC_I3C_IBI_CONTROLLER_TIMING_CONTEXT_VSEQ_SV

class smc_i3c_ibi_controller_timing_context_vseq extends
    smc_i3c_ibi_base_vseq;
  `uvm_object_utils(smc_i3c_ibi_controller_timing_context_vseq)

  localparam bit [1:0] TIMING_IDLE       = 2'd0;
  localparam bit [1:0] TIMING_AFTER_XFER = 2'd1;
  localparam bit [1:0] TIMING_BUSY_DEFER = 2'd2;
  localparam int unsigned TIMING_ALL     = 3;

  covergroup timing_context_cg with function sample(
      bit [1:0] context,
      bit request_while_busy,
      bit deferred,
      bit ack,
      bit hci_ok);
    option.per_instance = 1;
    cp_context: coverpoint context {
      bins idle       = {TIMING_IDLE};
      bins after_xfer = {TIMING_AFTER_XFER};
      bins busy_defer = {TIMING_BUSY_DEFER};
    }
    cp_request_busy: coverpoint request_while_busy {
      bins no  = {0};
      bins yes = {1};
    }
    cp_deferred: coverpoint deferred {
      bins immediate = {0};
      bins was_deferred = {1};
    }
    cp_ack: coverpoint ack {
      bins nack = {0};
      bins ack  = {1};
    }
    cp_hci: coverpoint hci_ok {
      bins fail = {0};
      bins pass = {1};
    }
    x_context_result: cross cp_context, cp_ack, cp_hci;
  endgroup

  function new(
      string name = "smc_i3c_ibi_controller_timing_context_vseq");
    super.new(name);
    timing_context_cg = new();
  endfunction

`ifdef SMC_USE_I3C_RTL
`ifdef SMC_USE_I3C_RAL
  protected task wait_for_event(uvm_event event_handle,
                                input string operation);
    for (int unsigned cycle = 0;
         cycle < vseq_ctx.cfg.ibi_timeout_cycles; cycle++) begin
      if (event_handle.is_on())
        return;
      @(posedge vseq_ctx.cfg.vif.clk);
    end
    `uvm_fatal("IBI_TIMING_EVENT_TIMEOUT",
               $sformatf("%s timed out", operation))
  endtask

  protected task run_normal_write(
      input bit [7:0] payload,
      input bit [3:0] transaction_id,
      input bit request_during_busy,
      input bit request_after_stop,
      input string operation);
    smc_i3c_target_private_write_seq target_seq;
    smc_i3c_controller_hci_helper #(TB_ADDR_WIDTH, TB_DATA_WIDTH)
      hci_helper;
    bit target_done;
    bit [TB_DATA_WIDTH-1:0] response_descriptor;
    bit [1:0] response_port_response;
    bit parity_ok;
    bit [7:0] observed_byte;
    bit observed_t_bit;

    hci_helper = vseq_ctx.i3c_controller_hci_helper;
    target_seq = smc_i3c_target_private_write_seq::type_id::create(
      "target_private_write_seq");
    target_seq.target_addr = vseq_ctx.cfg.ibi_target_addr;
    target_seq.expected_byte_count = 1;
    target_seq.pause_before_data = request_during_busy;
    target_done = 1'b0;

    vseq_ctx.cfg.vif.i3c_controller_sva_check_enable = 1'b0;
    vseq_ctx.cfg.vif.i3c_timing_normal_active = 1'b1;
    fork : normal_target_thread
      begin
        target_seq.start(vseq_ctx.i3c_sqr);
        target_done = 1'b1;
      end
    join_none

    hci_helper.issue_dat_private_write(
      vseq_ctx.cfg.ibi_controller_dat_index,
      payload, transaction_id, this);

    if (request_during_busy) begin
      wait_for_event(target_seq.address_seen_event,
                     {operation, " wait for address phase"});
      if (!target_seq.address_matched)
        `uvm_fatal("IBI_TIMING_NORMAL_ADDRESS",
                   $sformatf("%s observed address=0x%02h RNW=%0b expected=0x%02h/0",
                             operation, target_seq.observed_addr,
                             target_seq.observed_dir,
                             vseq_ctx.cfg.ibi_target_addr))
      vseq_ctx.cfg.vif.i3c_timing_ibi_pending = 1'b1;
      vseq_ctx.cfg.ibi_timing_pending_busy_samples++;
      `uvm_info("IBI_TIMING_MARKER",
                $sformatf("%s: IBI request became pending during active address phase at %0t",
                          operation, $time),
                UVM_HIGH)
      // Hold the request across real bus clocks while the Controller is
      // waiting for its address ACK. This is busy context, but no IBI item is
      // submitted to the driver until the legal post-STOP window.
      repeat (2)
        @(posedge vseq_ctx.cfg.vif.clk);
      target_seq.continue_event.trigger();
    end

    for (int unsigned cycle = 0;
         cycle < vseq_ctx.cfg.ibi_timeout_cycles; cycle++) begin
      if (target_done)
        break;
      @(posedge vseq_ctx.cfg.vif.clk);
    end
    if (!target_done) begin
      disable normal_target_thread;
      `uvm_fatal("IBI_TIMING_NORMAL_TIMEOUT",
                 $sformatf("%s timed out waiting for private write",
                           operation))
    end
    disable normal_target_thread;
    wait_bus_idle({operation, " wait for STOP"});
    vseq_ctx.cfg.vif.i3c_timing_normal_active = 1'b0;
    if (request_after_stop)
      vseq_ctx.cfg.vif.i3c_timing_ibi_pending = 1'b1;
    if (request_after_stop)
      `uvm_info("IBI_TIMING_MARKER",
                $sformatf("%s: IBI request became pending immediately after STOP at %0t",
                          operation, $time),
                UVM_HIGH)

    if (!target_seq.address_response_valid ||
        !target_seq.transfer_response_valid ||
        !target_seq.address_matched ||
        !target_seq.transfer_done)
      `uvm_fatal("IBI_TIMING_NORMAL_TRANSFER",
                 $sformatf("%s incomplete: addr_rsp=%0b data_rsp=%0b match=%0b done=%0b",
                           operation,
                           target_seq.address_response_valid,
                           target_seq.transfer_response_valid,
                           target_seq.address_matched,
                           target_seq.transfer_done))
    observed_byte = target_seq.observed_data.size() ?
                      target_seq.observed_data[0] : 8'h00;
    observed_t_bit = target_seq.observed_t_bits.size() ?
                       target_seq.observed_t_bits[0] : 1'b0;
    if ((target_seq.observed_data.size() != 1) ||
        (observed_byte !== payload))
      `uvm_error("IBI_TIMING_NORMAL_DATA",
                 $sformatf("%s expected payload=0x%02h observed_count=%0d observed=0x%02h",
                           operation, payload,
                           target_seq.observed_data.size(),
                           target_seq.observed_data.size() ?
                             target_seq.observed_data[0] : 8'h00))
    parity_ok = (target_seq.observed_data.size() == 1) &&
                (target_seq.observed_t_bits.size() == 1) &&
                (((^observed_byte) ^ observed_t_bit) === 1'b1);
    if (!parity_ok)
      `uvm_error("IBI_TIMING_NORMAL_TBIT",
                 $sformatf("%s observed invalid data/T-bit parity",
                           operation))

    repeat (10)
      @(posedge vseq_ctx.cfg.vif.clk);
    vseq_ctx.i3c_csr_helper.read_response_descriptor(
      response_descriptor, response_port_response, this);
    if (response_port_response != 2'b00)
      `uvm_error("IBI_TIMING_NORMAL_RESPONSE",
                 $sformatf("%s response-port read failed response=%0b",
                           operation, response_port_response))
    else begin
      if (response_descriptor[31:28] !== 4'h0)
        `uvm_error("IBI_TIMING_NORMAL_RESPONSE",
                   $sformatf("%s error status=%0h descriptor=0x%08h",
                             operation, response_descriptor[31:28],
                             response_descriptor))
      if (response_descriptor[27:24] !== transaction_id)
        `uvm_error("IBI_TIMING_NORMAL_RESPONSE",
                   $sformatf("%s TID expected=%0d actual=%0d",
                             operation, transaction_id,
                             response_descriptor[27:24]))
      if (response_descriptor[15:0] !== 16'd0)
        `uvm_error("IBI_TIMING_NORMAL_RESPONSE",
                   $sformatf("%s remaining length expected=0 actual=%0d",
                             operation, response_descriptor[15:0]))
    end

    vseq_ctx.cfg.ibi_timing_normal_xfer_checks++;
    if (request_during_busy)
      vseq_ctx.cfg.ibi_timing_no_start_busy_checks++;
    `uvm_info("IBI_TIMING_NORMAL",
              $sformatf("%s completed: DA=0x%02h payload=0x%02h T=%0b response=0x%08h pending=%0b",
                        operation, target_seq.observed_addr,
                        observed_byte, observed_t_bit,
                        response_descriptor,
                        vseq_ctx.cfg.vif.i3c_timing_ibi_pending),
              UVM_HIGH)
  endtask

  protected task check_no_ibi_before_release(input string operation);
    bit [31:0] interrupt_status;

    if (vseq_ctx.cfg.vif.i3c_irq !== 1'b0)
      `uvm_error("IBI_TIMING_EARLY_IRQ",
                 $sformatf("%s: IRQ asserted before legal IBI START",
                           operation))
    vseq_ctx.i3c_controller_hci_helper.read_ibi_status(
      interrupt_status, this);
    if (interrupt_status[2])
      `uvm_error("IBI_TIMING_EARLY_RECORD",
                 $sformatf("%s: IBI threshold status set before legal START: status=0x%08h",
                           operation, interrupt_status))
  endtask

  protected task run_autonomous_ibi(
      input bit [1:0] context,
      input bit request_while_busy,
      input bit deferred,
      input string operation);
    smc_i3c_target_send_ibi_seq target_seq;
    smc_i3c_controller_hci_helper #(TB_ADDR_WIDTH, TB_DATA_WIDTH)
      hci_helper;
    bit target_done;
    bit [31:0] interrupt_status;
    bit [31:0] descriptor;
    byte unsigned hci_data[$];
    int unsigned expected_before;
    int unsigned actual_before;
    int unsigned completion_before;
    int unsigned mismatch_before;
    bit hci_ok;
    bit [7:0] observed_mdb;
    logic previous_scl;
    logic previous_sda;
    int unsigned scl_edges;
    int unsigned sda_edges;

    hci_helper = vseq_ctx.i3c_controller_hci_helper;
    target_seq = smc_i3c_target_send_ibi_seq::type_id::create(
      "target_ibi_seq");
    target_seq.target_addr = vseq_ctx.cfg.ibi_target_addr;
    target_seq.mdb_present = 1'b1;
    target_seq.mdb = vseq_ctx.cfg.ibi_basic_mdb;
    target_seq.payload.delete();
    target_seq.start_on_idle = 1'b1;
    target_done = 1'b0;
    previous_scl = vseq_ctx.cfg.i3c_vif.scl_i;
    previous_sda = vseq_ctx.cfg.i3c_vif.sda_i;
    scl_edges = 0;
    sda_edges = 0;

    expected_before = vseq_ctx.cfg.ibi_controller_expected_events;
    actual_before = vseq_ctx.cfg.ibi_controller_actual_events;
    completion_before = vseq_ctx.cfg.ibi_sb_completion_count;
    mismatch_before = vseq_ctx.cfg.ibi_sb_mismatch_count;
    vseq_ctx.cfg.ibi_bus_state =
      (context == TIMING_IDLE) ? 2'd0 : 2'd2;
    vseq_ctx.cfg.vif.i3c_controller_expected_ack = 1'b1;
    if (!vseq_ctx.cfg.vif.i3c_timing_ibi_pending)
      `uvm_fatal("IBI_TIMING_REQUEST",
                 $sformatf("%s attempted IBI without a pending request",
                           operation))
    if (vseq_ctx.cfg.vif.i3c_timing_normal_active ||
        (vseq_ctx.cfg.i3c_vif.scl_i !== 1'b1) ||
        (vseq_ctx.cfg.i3c_vif.sda_i !== 1'b1))
      `uvm_fatal("IBI_TIMING_ILLEGAL_START",
                 $sformatf("%s release is not legal: normal_active=%0b SCL/SDA=%b/%b",
                           operation,
                           vseq_ctx.cfg.vif.i3c_timing_normal_active,
                           vseq_ctx.cfg.i3c_vif.scl_i,
                           vseq_ctx.cfg.i3c_vif.sda_i))
    vseq_ctx.cfg.vif.i3c_controller_sva_check_enable = 1'b1;
    vseq_ctx.cfg.vif.i3c_timing_ibi_start_allowed = 1'b1;
    `uvm_info("IBI_TIMING_MARKER",
              $sformatf("%s: physical IBI START released after legal bus window at %0t",
                        operation, $time),
              UVM_HIGH)

    fork : autonomous_ibi_thread
      begin
        target_seq.start(vseq_ctx.i3c_sqr);
        target_done = 1'b1;
      end
    join_none
    for (int unsigned cycle = 0;
         cycle < vseq_ctx.cfg.ibi_timeout_cycles; cycle++) begin
      if (target_done)
        break;
      @(posedge vseq_ctx.cfg.vif.clk);
      if (vseq_ctx.cfg.i3c_vif.scl_i !== previous_scl)
        scl_edges++;
      if (vseq_ctx.cfg.i3c_vif.sda_i !== previous_sda)
        sda_edges++;
      previous_scl = vseq_ctx.cfg.i3c_vif.scl_i;
      previous_sda = vseq_ctx.cfg.i3c_vif.sda_i;
    end
    if (!target_done) begin
      disable autonomous_ibi_thread;
      `uvm_fatal("IBI_TIMING_IBI_TIMEOUT",
                 $sformatf("%s timed out waiting for autonomous IBI: response_valid=%0b ACK=%0b SCL edges=%0d SDA edges=%0d final SCL/SDA=%b/%b DUT SCL_OE/SDA_OE=%b/%b IRQ=%b",
                           operation, target_seq.response_valid,
                           target_seq.observed_ack, scl_edges, sda_edges,
                           vseq_ctx.cfg.i3c_vif.scl_i,
                           vseq_ctx.cfg.i3c_vif.sda_i,
                           vseq_ctx.cfg.vif.i3c_scl_oe,
                           vseq_ctx.cfg.vif.i3c_sda_oe,
                           vseq_ctx.cfg.vif.i3c_irq))
    end
    disable autonomous_ibi_thread;
    vseq_ctx.cfg.vif.i3c_controller_sva_check_enable = 1'b0;
    if (!target_seq.observed_ack)
      `uvm_fatal("IBI_TIMING_IBI_NACK",
                 $sformatf("%s: Controller NACKed legal autonomous IBI from DA=0x%02h",
                           operation, vseq_ctx.cfg.ibi_target_addr))

    wait_irq(1'b1, {operation, " wait for IBI IRQ"});
    hci_helper.read_ibi_status(interrupt_status, this);
    if (!interrupt_status[2])
      `uvm_error("IBI_TIMING_IRQ_STATUS",
                 $sformatf("%s IRQ asserted with status=0x%08h",
                           operation, interrupt_status))
    hci_helper.read_ibi_record(descriptor, hci_data, this);
    wait_scoreboard_completion(
      completion_before + 1, {operation, " scoreboard completion"});
    wait_irq(1'b0, {operation, " wait for IRQ clear"});

    hci_ok = 1'b1;
    if (descriptor[15:8] !== {vseq_ctx.cfg.ibi_target_addr, 1'b1}) begin
      hci_ok = 1'b0;
      `uvm_error("IBI_TIMING_IBI_ID",
                 $sformatf("%s HCI IBI_ID expected {DA,RnW}=0x%02h actual=0x%02h",
                           operation,
                           {vseq_ctx.cfg.ibi_target_addr, 1'b1},
                           descriptor[15:8]))
    end
    observed_mdb = hci_data.size() ? hci_data[0] : 8'h00;
    if ((hci_data.size() != 1) ||
        (observed_mdb !== vseq_ctx.cfg.ibi_basic_mdb)) begin
      hci_ok = 1'b0;
      `uvm_error("IBI_TIMING_IBI_DATA",
                 $sformatf("%s expected MDB=0x%02h count=1 actual MDB=0x%02h count=%0d",
                           operation, vseq_ctx.cfg.ibi_basic_mdb,
                           hci_data.size() ? hci_data[0] : 8'h00,
                           hci_data.size()))
    end
    if ((vseq_ctx.cfg.ibi_controller_expected_events !=
           expected_before + 1) ||
        (vseq_ctx.cfg.ibi_controller_actual_events !=
           actual_before + 1)) begin
      hci_ok = 1'b0;
      `uvm_error("IBI_TIMING_EVENT_COUNT",
                 $sformatf("%s expected/actual deltas must be 1/1, totals=%0d/%0d before=%0d/%0d",
                           operation,
                           vseq_ctx.cfg.ibi_controller_expected_events,
                           vseq_ctx.cfg.ibi_controller_actual_events,
                           expected_before, actual_before))
    end
    if (vseq_ctx.cfg.ibi_sb_mismatch_count != mismatch_before)
      hci_ok = 1'b0;

    timing_context_cg.sample(context, request_while_busy, deferred,
                             target_seq.observed_ack, hci_ok);
    vseq_ctx.cfg.vif.i3c_timing_ibi_pending = 1'b0;
    vseq_ctx.cfg.vif.i3c_timing_ibi_start_allowed = 1'b0;
    `uvm_info("IBI_TIMING_IBI",
              $sformatf("%s completed: descriptor=0x%08h MDB=0x%02h hci_ok=%0b",
                        operation, descriptor, observed_mdb, hci_ok),
              UVM_HIGH)
  endtask

  protected task run_idle_context();
    // Keep this context independent from AFTER_XFER. Starting with a normal
    // transfer would leave the result ambiguous between idle-start handling
    // and the Controller's post-transfer mode restoration.
    vseq_ctx.i3c_controller_hci_helper.wait_bus_available(this);
    vseq_ctx.cfg.vif.i3c_timing_ibi_pending = 1'b1;
    `uvm_info("IBI_TIMING_MARKER",
              $sformatf("IDLE: request asserted after Bus Available at %0t",
                        $time),
              UVM_HIGH)
    run_autonomous_ibi(TIMING_IDLE, 1'b0, 1'b0, "IDLE");
    run_normal_write(8'h91, 4'h1, 1'b0, 1'b0,
                     "IDLE forward-progress sentinel");
  endtask

  protected task run_after_transfer_context();
    run_normal_write(8'h42, 4'h3, 1'b0, 1'b1,
                     "AFTER_XFER normal write");
    check_no_ibi_before_release("AFTER_XFER pending window");
    vseq_ctx.i3c_controller_hci_helper.wait_bus_available(this);
    vseq_ctx.cfg.ibi_timing_retry_after_taval_samples++;
    run_autonomous_ibi(TIMING_AFTER_XFER, 1'b0, 1'b1,
                       "AFTER_XFER");
    run_normal_write(8'ha2, 4'h4, 1'b0, 1'b0,
                     "AFTER_XFER forward-progress sentinel");
  endtask

  protected task run_busy_defer_context();
    run_normal_write(8'h53, 4'h5, 1'b1, 1'b0,
                     "BUSY_DEFER normal write");
    check_no_ibi_before_release("BUSY_DEFER pending window");
    vseq_ctx.i3c_controller_hci_helper.wait_bus_available(this);
    vseq_ctx.cfg.ibi_timing_retry_after_taval_samples++;
    run_autonomous_ibi(TIMING_BUSY_DEFER, 1'b1, 1'b1,
                       "BUSY_DEFER");
    run_normal_write(8'hb3, 4'h6, 1'b0, 1'b0,
                     "BUSY_DEFER forward-progress sentinel");
  endtask
`endif
`endif

  virtual task body();
    bit [31:0] interrupt_status;

    super.body();
    if (!vseq_ctx.cfg.has_rtl)
      `uvm_fatal("IBI_TIMING_MODE",
                 "Controller timing-context test requires DUT_MODE=rtl")
    if (vseq_ctx.cfg.ibi_dut_role != SMC_I3C_IBI_DUT_CONTROLLER)
      `uvm_fatal("IBI_TIMING_ROLE",
                 "Controller timing-context test requires DUT-controller role")

`ifdef SMC_USE_I3C_RTL
`ifdef SMC_USE_I3C_RAL
    if ((vseq_ctx.i3c_sqr == null) ||
        (vseq_ctx.i3c_controller_hci_helper == null))
      `uvm_fatal("IBI_TIMING_CFG",
                 "I3C Target sequencer or Controller HCI helper is missing")

    vseq_ctx.cfg.vif.i3c_controller_sva_check_enable = 1'b0;
    vseq_ctx.cfg.vif.i3c_timing_normal_active = 1'b0;
    vseq_ctx.cfg.vif.i3c_timing_ibi_pending = 1'b0;
    vseq_ctx.cfg.vif.i3c_timing_ibi_start_allowed = 1'b0;
    vseq_ctx.cfg.ibi_timing_pending_busy_samples = 0;
    vseq_ctx.cfg.ibi_timing_no_start_busy_checks = 0;
    vseq_ctx.cfg.ibi_timing_normal_xfer_checks = 0;
    vseq_ctx.cfg.ibi_timing_retry_after_taval_samples = 0;
    vseq_ctx.i3c_controller_hci_helper.initialize_controller_ibi(
      vseq_ctx.cfg.ibi_target_addr,
      vseq_ctx.cfg.ibi_controller_dat_index,
      this);
    wait_bus_idle("timing-context initial bus idle");
    wait_irq(1'b0, "timing-context initial IRQ low");
    vseq_ctx.i3c_controller_hci_helper.read_ibi_status(
      interrupt_status, this);
    if (interrupt_status[2])
      `uvm_fatal("IBI_TIMING_DIRTY_START",
                 $sformatf("IBI status queue is not empty at test start: status=0x%08h",
                           interrupt_status))

    case (vseq_ctx.cfg.ibi_timing_context)
      TIMING_IDLE:
        run_idle_context();
      TIMING_AFTER_XFER:
        run_after_transfer_context();
      TIMING_BUSY_DEFER:
        run_busy_defer_context();
      TIMING_ALL: begin
        run_idle_context();
        run_after_transfer_context();
        run_busy_defer_context();
      end
      default:
        `uvm_fatal("IBI_TIMING_CONTEXT",
                   $sformatf("Invalid timing context %0d",
                             vseq_ctx.cfg.ibi_timing_context))
    endcase

    if ((vseq_ctx.cfg.ibi_timing_context inside
           {TIMING_BUSY_DEFER, TIMING_ALL}) &&
        ((vseq_ctx.cfg.ibi_timing_pending_busy_samples == 0) ||
         (vseq_ctx.cfg.ibi_timing_no_start_busy_checks == 0)))
      `uvm_error("IBI_TIMING_BUSY_COVERAGE",
                 $sformatf("Missing busy deferral evidence pending=%0d no_start=%0d",
                           vseq_ctx.cfg.ibi_timing_pending_busy_samples,
                           vseq_ctx.cfg.ibi_timing_no_start_busy_checks))
    if ((vseq_ctx.cfg.ibi_timing_context inside
           {TIMING_AFTER_XFER, TIMING_BUSY_DEFER, TIMING_ALL}) &&
        (vseq_ctx.cfg.ibi_timing_retry_after_taval_samples == 0))
      `uvm_error("IBI_TIMING_RETRY_COVERAGE",
                 "No retry-after-T_AVAL evidence was sampled")
    if (vseq_ctx.cfg.ibi_sb_mismatch_count != 0)
      `uvm_error("IBI_TIMING_SCOREBOARD",
                 $sformatf("Controller IBI scoreboard mismatches=%0d",
                           vseq_ctx.cfg.ibi_sb_mismatch_count))

    vseq_ctx.cfg.vif.i3c_controller_sva_check_enable = 1'b0;
    vseq_ctx.cfg.vif.i3c_timing_normal_active = 1'b0;
    vseq_ctx.cfg.vif.i3c_timing_ibi_pending = 1'b0;
    vseq_ctx.cfg.vif.i3c_timing_ibi_start_allowed = 1'b0;
    `uvm_info("IBI_TIMING_SUMMARY",
              $sformatf("context=%0d normal_checks=%0d pending_busy=%0d no_start_busy=%0d retry_after_taval=%0d IBI expected/actual=%0d/%0d mismatches=%0d",
                        vseq_ctx.cfg.ibi_timing_context,
                        vseq_ctx.cfg.ibi_timing_normal_xfer_checks,
                        vseq_ctx.cfg.ibi_timing_pending_busy_samples,
                        vseq_ctx.cfg.ibi_timing_no_start_busy_checks,
                        vseq_ctx.cfg.ibi_timing_retry_after_taval_samples,
                        vseq_ctx.cfg.ibi_controller_expected_events,
                        vseq_ctx.cfg.ibi_controller_actual_events,
                        vseq_ctx.cfg.ibi_sb_mismatch_count),
              UVM_LOW)
`else
    `uvm_fatal("IBI_TIMING_RAL_BUILD",
               "Controller timing-context test requires SMC_USE_I3C_RAL")
`endif
`else
    `uvm_fatal("IBI_TIMING_RTL_BUILD",
               "Controller timing-context test requires SMC_USE_I3C_RTL")
`endif
  endtask
endclass : smc_i3c_ibi_controller_timing_context_vseq

`endif // SMC_I3C_IBI_CONTROLLER_TIMING_CONTEXT_VSEQ_SV
