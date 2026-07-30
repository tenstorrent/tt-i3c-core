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
// File        : smc_i3c_ibi_controller_policy_vseq.sv
// Description : Virtual sequence for I3C IBI controller policy.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-26
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_CONTROLLER_POLICY_VSEQ_SV
`define SMC_I3C_IBI_CONTROLLER_POLICY_VSEQ_SV

// Exercises the four DAT policy cases (accept / reject / payload-disabled /
// no-match). The pinned RTL services only the first IBI per simulation
// (Defect A.3) and re-enters the IBI state badly on a second record. Two
// source-level modes (no plusarg): RUN_ALL_IN_ONE_SEQ=1 (current default)
// chains all four cases in one sim as a diagnostic -- case 1 passes, cases
// 2-4 fail non-fatally on this RTL (A.3) and the controller scoreboard
// summary counts them; RUN_ALL_IN_ONE_SEQ=0 runs one selected
// ACTIVE_POLICY_CASE per sim so each case reports its real result from a
// clean reset. Checks that would abort on a known RTL
// limitation are downgraded from UVM_FATAL to UVM_ERROR (soft waits plus a
// per-case bus drain) so the sequence completes and reports failures instead
// of killing the simulation. See the test header
// (smc_i3c_ibi_controller_policy_test.sv) for the specific RTL bugs.
class smc_i3c_ibi_controller_policy_vseq extends smc_i3c_ibi_base_vseq;
  `uvm_object_utils(smc_i3c_ibi_controller_policy_vseq)

  localparam int unsigned POLICY_CASE_COUNT = 4;
  // Sustained-idle window (in clocks) required between cases; must exceed the
  // controller T_AVAL bus-available time so the availability check cannot trip
  // on the previous case's trailing bus activity.
  localparam int unsigned POLICY_BUS_SETTLE_CYCLES = 400;
  // Bound for the target-IBI completion wait. A successful case completes well
  // under this; the 2nd+ IBI in a sim is known to hang on this RTL (see the
  // test header), so cap the wait far below cfg.ibi_timeout_cycles (200k) to
  // keep each expected hang cheap (~200 us) instead of burning ~2 ms.
  localparam int unsigned POLICY_TARGET_TIMEOUT_CYCLES = 20_000;

  // === Policy-case gating (source-level; no plusarg) =======================
  // The pinned RTL services only the first IBI per simulation (Defect A.3) and
  // re-enters the IBI state badly on a second record (DAT index can go X), so
  // more than one policy case cannot cleanly share a simulation today. The two
  // modes below trade diagnostic breadth (all cases, later ones fail
  // non-fatally) against clean per-case results (one case per sim).
  //   RUN_ALL_IN_ONE_SEQ : 1 (current default) = diagnostic mode: chain all
  //                        four cases in one sim. Case 1 passes; cases 2-4
  //                        fail NON-FATALLY on this RTL (A.3 driver wedge, all
  //                        waits are bounded) and the controller scoreboard
  //                        summary counts them (Cases launched / incomplete).
  //                        0 = run one selected ACTIVE_POLICY_CASE per sim.
  //   ACTIVE_POLICY_CASE : which case (1..4) runs when RUN_ALL_IN_ONE_SEQ==0.
  //                        1=DAT accept, 2=DAT reject, 3=payload disabled,
  //                        4=DAT no-match. Cases 1-3 pass on this RTL; case 4
  //                        is a known-fail (Defect A.2) reported, never waived.
  // Keeping the switch in source makes the enabled/disabled state visible and
  // lets it flip back cleanly for regression when the RTL is fixed.
  localparam bit          RUN_ALL_IN_ONE_SEQ = 1'b0; // capture A.2: one IBI per sim
  localparam int unsigned ACTIVE_POLICY_CASE = 4;    // 4 = DAT no-match (bug); revert to 1 for regression

  function new(string name = "smc_i3c_ibi_controller_policy_vseq");
    super.new(name);
  endfunction

`ifdef SMC_USE_I3C_RTL
`ifdef SMC_USE_I3C_RAL
  // Mirrors i3c_pkg::is_i3c_rsvd_addr from the pinned core. The RTL package is
  // not imported into smc_peripherals_vseq_pkg, so replicate the reserved
  // address set here (same convention as
  // smc_i3c_ibi_base_test::is_reserved_dynamic_addr).
  protected function bit is_reserved_dynamic_addr(bit [6:0] addr);
    return addr inside {[7'h00:7'h07], 7'h3e, 7'h5e, 7'h6e, 7'h76,
                        [7'h78:7'h7f]};
  endfunction

  protected function bit [6:0] select_unmatched_dat_addr(
      bit [6:0] target_addr);
    bit [6:0] candidate;

    for (int unsigned offset = 1;
         offset < (1 << $bits(target_addr)); offset++) begin
      candidate = target_addr + offset;
      if ((candidate != target_addr) &&
          !is_reserved_dynamic_addr(candidate))
        return candidate;
    end
    `uvm_fatal("IBI_CTRL_POLICY_ADDR",
               "Unable to select a legal unmatched DAT address")
    return target_addr;
  endfunction

  protected task wait_target_completion(
      ref bit target_transfer_done,
      input string case_name);
    if (target_transfer_done)
      return;

    repeat (POLICY_TARGET_TIMEOUT_CYCLES) begin
      @(posedge vseq_ctx.cfg.vif.clk);
      if (target_transfer_done)
        return;
    end

    `uvm_error("IBI_CTRL_POLICY_BUS_TIMEOUT",
               $sformatf("%s: target IBI bus transfer timed out (known RTL limitation)",
                         case_name))
  endtask

  // Soft (non-fatal) mirrors of the base-class waits. A timeout here is a
  // known RTL limitation (see the test header), so it is reported as
  // UVM_ERROR and the sequence continues, letting every policy case run to
  // completion instead of aborting the simulation on the first blockage.
  protected task soft_wait_irq(bit expected, string operation,
                               output bit ok);
    ok = 1'b0;
    for (int unsigned cycle = 0;
         cycle < vseq_ctx.cfg.ibi_timeout_cycles; cycle++) begin
      if (vseq_ctx.cfg.vif.i3c_irq === expected) begin
        ok = 1'b1;
        return;
      end
      @(posedge vseq_ctx.cfg.vif.clk);
    end
    `uvm_error("IBI_CTRL_POLICY_IRQ",
               $sformatf("%s: i3c_irq did not become %0b (known RTL limitation)",
                         operation, expected))
  endtask

  protected task soft_wait_scoreboard(int unsigned expected_count,
                                      string operation, output bit ok);
    ok = 1'b0;
    for (int unsigned cycle = 0;
         cycle < vseq_ctx.cfg.ibi_timeout_cycles; cycle++) begin
      if (vseq_ctx.cfg.ibi_sb_completion_count >= expected_count) begin
        ok = 1'b1;
        return;
      end
      @(posedge vseq_ctx.cfg.vif.clk);
    end
    `uvm_error("IBI_CTRL_POLICY_SB_WAIT",
               $sformatf("%s: scoreboard completion count did not reach %0d (actual=%0d)",
                         operation, expected_count,
                         vseq_ctx.cfg.ibi_sb_completion_count))
  endtask

  // Absorb any trailing controller bus activity from the previous case (an
  // IBI-hijacked private write can extend past its own IBI) so the next case
  // starts from a sustained-idle bus. Restarts the idle window on any activity.
  protected task soft_wait_bus_settled(string operation, output bit ok);
    int unsigned idle_run;
    ok = 1'b0;
    idle_run = 0;
    for (int unsigned cycle = 0;
         cycle < vseq_ctx.cfg.ibi_timeout_cycles; cycle++) begin
      if ((vseq_ctx.cfg.i3c_vif.scl_i === 1'b1) &&
          (vseq_ctx.cfg.i3c_vif.sda_i === 1'b1))
        idle_run++;
      else
        idle_run = 0;
      if (idle_run >= POLICY_BUS_SETTLE_CYCLES) begin
        ok = 1'b1;
        return;
      end
      @(posedge vseq_ctx.cfg.vif.clk);
    end
    `uvm_error("IBI_CTRL_POLICY_BUS_SETTLE",
               $sformatf("%s: bus never settled idle for %0d cycles",
                         operation, POLICY_BUS_SETTLE_CYCLES))
  endtask

  // Bounded wait for the Device driver to arm this case's IBI. Once a prior
  // un-serviced IBI wedges the vendored base driver inside super.
  // drive_device_item, killing the sequence cannot free it, so the driver
  // never dequeues this case's item and the arm event never fires. Bound the
  // wait so the simulation terminates (and dumps) instead of hanging forever.
  protected task soft_wait_armed(uvm_event armed_event, string case_name,
                                 output bit ok);
    ok = 1'b0;
    fork : arm_guard
      begin
        armed_event.wait_on();
        ok = 1'b1;
      end
      begin
        repeat (POLICY_TARGET_TIMEOUT_CYCLES)
          @(posedge vseq_ctx.cfg.vif.clk);
      end
    join_any
    disable arm_guard;
    if (!ok)
      `uvm_error("IBI_CTRL_POLICY_ARM_TIMEOUT",
                 $sformatf({"%s: target IBI never armed; I3C Device driver ",
                            "is wedged by a prior un-serviced IBI (known RTL ",
                            "limitation)"}, case_name))
  endtask

  protected task run_policy_case(
      input string case_name,
      input bit [6:0] dat_addr,
      input bit dat_reject,
      input bit dat_payload,
      input bit expected_ack,
      input int unsigned completion_target,
      input bit [3:0] command_id,
      input smc_i3c_controller_hci_helper #(
        TB_ADDR_WIDTH, TB_DATA_WIDTH) hci_helper);
    smc_i3c_target_send_ibi_seq target_seq;
    bit [31:0] interrupt_status;
    bit [31:0] descriptor;
    byte unsigned hci_data[$];
    bit target_transfer_done;
    bit wait_ok;
    uvm_event target_armed_event;

    // Count every launched case up front (before arm/completion) so the
    // controller scoreboard summary accounts for cases that never complete on
    // the bus (RTL A.3 wedge) instead of silently reporting PASS.
    vseq_ctx.cfg.ibi_controller_attempt_cases++;

    hci_helper.program_dat_entry(
      vseq_ctx.cfg.ibi_controller_dat_index,
      dat_addr, '0, dat_reject, dat_payload, this);
    // Drain any trailing controller activity from the previous case so this
    // case starts from a clean, sustained-idle bus (see test header).
    soft_wait_bus_settled({case_name, ": drain bus before availability"},
                          wait_ok);
    soft_wait_irq(1'b0, {case_name, ": verify IRQ initially low"}, wait_ok);

    vseq_ctx.cfg.vif.i3c_controller_expected_ack = expected_ack;
    target_seq = smc_i3c_target_send_ibi_seq::type_id::create("target_seq");
    target_seq.target_addr = vseq_ctx.cfg.ibi_target_addr;
    target_seq.mdb_present = 1'b1;
    target_seq.mdb = vseq_ctx.cfg.ibi_basic_mdb;
    target_seq.payload.push_back(8'h51);
    target_seq.payload.push_back(8'hae);
    target_seq.start_on_idle = 1'b0;

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

    soft_wait_armed(target_armed_event, case_name, wait_ok);
    if (!wait_ok) begin
      // Driver wedged by a prior case; this case cannot run. Clean up and let
      // the end-of-test summary report the missing event as UVM_ERROR.
      target_seq.kill();
      disable target_ibi_driver;
      return;
    end
    vseq_ctx.cfg.ibi_bus_state = 2'd1;
    hci_helper.issue_dat_private_write(
      vseq_ctx.cfg.ibi_controller_dat_index,
      8'hc3, command_id, this);
    wait_target_completion(target_transfer_done, case_name);
    // Gracefully end the target sequence before disabling its fork so UVM does
    // not emit SEQPRTZMB (auto-kill of a still-running child) when the IBI hung.
    if (!target_transfer_done)
      target_seq.kill();
    disable target_ibi_driver;
    if (!target_transfer_done) begin
      `uvm_error("IBI_CTRL_POLICY_BUS",
                 $sformatf("%s: target IBI did not complete (known RTL limitation)",
                           case_name))
      return;
    end
    if (target_seq.observed_ack !== expected_ack)
      `uvm_error("IBI_CTRL_POLICY_RESPONSE",
                 $sformatf("%s: expected ACK=%0b, observed ACK=%0b (known RTL limitation)",
                           case_name, expected_ack,
                           target_seq.observed_ack))

    soft_wait_irq(1'b1, {case_name, ": wait for HCI IBI IRQ"}, wait_ok);
    if (!wait_ok)
      return;
    hci_helper.read_ibi_status(interrupt_status, this);
    if (interrupt_status[2] !== 1'b1)
      `uvm_error("IBI_CTRL_POLICY_STATUS",
                 $sformatf("%s: IBI_STATUS_THLD_STAT is low: status=0x%08h",
                           case_name, interrupt_status))
    hci_helper.read_ibi_record(descriptor, hci_data, this);
    if (descriptor[31] !== !expected_ack)
      `uvm_error("IBI_CTRL_POLICY_DESCRIPTOR_STATUS",
                 $sformatf("%s: expected IBI_STATUS=%0b, descriptor=0x%08h",
                           case_name, !expected_ack, descriptor))
    if (descriptor[30] !== 1'b0)
      `uvm_error("IBI_CTRL_POLICY_DESCRIPTOR_ERROR",
                 $sformatf("%s: policy response unexpectedly set ERROR: descriptor=0x%08h",
                           case_name, descriptor))
    if (!expected_ack &&
        ((descriptor[7:0] !== 8'd0) || (hci_data.size() != 0)))
      `uvm_error("IBI_CTRL_POLICY_REJECTED_DATA",
                 $sformatf("%s: NACK status committed DATA_LENGTH=%0d bytes=%0d",
                           case_name, descriptor[7:0], hci_data.size()))
    soft_wait_scoreboard(
      completion_target, {case_name, ": wait for scoreboard"}, wait_ok);
    soft_wait_irq(1'b0, {case_name, ": wait for IRQ clear"}, wait_ok);
    hci_helper.read_ibi_status(interrupt_status, this);
    if (interrupt_status[2] !== 1'b0)
      `uvm_error("IBI_CTRL_POLICY_STATUS_CLEAR",
                 $sformatf("%s: threshold status remained set after drain: 0x%08h",
                           case_name, interrupt_status))

    `uvm_info("IBI_CTRL_POLICY_CASE",
              $sformatf("%s: DAT_DA=0x%02h target_DA=0x%02h reject=%0b payload=%0b ACK=%0b",
                        case_name, dat_addr,
                        vseq_ctx.cfg.ibi_target_addr, dat_reject,
                        dat_payload, expected_ack),
              UVM_LOW)
  endtask

  // Maps a 1..4 case index to run_policy_case. completion_target is the
  // cumulative scoreboard count expected after this case: it equals the case
  // index when chaining all four, but is 1 for a single-case simulation
  // (a fresh sim starts the scoreboard count at zero).
  protected task run_policy_case_by_index(
      input int unsigned idx,
      input int unsigned completion_target,
      input bit [6:0] unmatched_dat_addr,
      input smc_i3c_controller_hci_helper #(
        TB_ADDR_WIDTH, TB_DATA_WIDTH) hci_helper);
    case (idx)
      1: run_policy_case("DAT accept", vseq_ctx.cfg.ibi_target_addr,
                         1'b0, 1'b1, 1'b1, completion_target, 4'h1,
                         hci_helper);
      2: run_policy_case("DAT reject", vseq_ctx.cfg.ibi_target_addr,
                         1'b1, 1'b1, 1'b0, completion_target, 4'h2,
                         hci_helper);
      3: run_policy_case("payload disabled", vseq_ctx.cfg.ibi_target_addr,
                         1'b0, 1'b0, 1'b0, completion_target, 4'h3,
                         hci_helper);
      4: run_policy_case("DAT no-match", unmatched_dat_addr,
                         1'b0, 1'b1, 1'b0, completion_target, 4'h4,
                         hci_helper);
      default:
        `uvm_fatal("IBI_CTRL_POLICY_CASE_SEL",
                   $sformatf("ACTIVE_POLICY_CASE must be 1..4, got %0d", idx))
    endcase
  endtask
`endif
`endif

  virtual task body();
    super.body();
    if (!vseq_ctx.cfg.has_rtl)
      `uvm_fatal("IBI_CTRL_POLICY_MODE",
                 "Controller policy test requires DUT_MODE=rtl")
    if (vseq_ctx.cfg.ibi_dut_role != SMC_I3C_IBI_DUT_CONTROLLER)
      `uvm_fatal("IBI_CTRL_POLICY_ROLE",
                 "Controller policy vseq requires DUT-controller role")

`ifdef SMC_USE_I3C_RTL
`ifdef SMC_USE_I3C_RAL
    begin
      smc_i3c_controller_hci_helper #(TB_ADDR_WIDTH, TB_DATA_WIDTH)
        hci_helper;
      bit [6:0] unmatched_dat_addr;
      bit setup_ok;
      int unsigned cases_run;

      hci_helper = vseq_ctx.i3c_controller_hci_helper;
      if (hci_helper == null)
        `uvm_fatal("IBI_CTRL_POLICY_HELPER",
                   "Controller HCI helper is not available")

      hci_helper.initialize_controller_ibi(
        vseq_ctx.cfg.ibi_target_addr,
        vseq_ctx.cfg.ibi_controller_dat_index,
        this);
      // Sustained-idle drain subsumes the T_AVAL bus-available window; use
      // the soft variant so a slow initial settle reports UVM_ERROR instead
      // of the shared helper's fatal (see the test header).
      soft_wait_bus_settled(
        "wait for idle bus before Controller policy test", setup_ok);
      soft_wait_irq(1'b0, "verify Controller policy IRQ initially low",
                    setup_ok);
      hci_helper.enable_broadcast_header(this);
      unmatched_dat_addr =
        select_unmatched_dat_addr(vseq_ctx.cfg.ibi_target_addr);

      // RUN_ALL_IN_ONE_SEQ=1 (default): chain all four cases in one sim
      // (diagnostic; cases 2-4 fail non-fatally on this RTL, A.3). =0: run
      // one selected ACTIVE_POLICY_CASE as the sim's only IBI.
      if (RUN_ALL_IN_ONE_SEQ) begin
        for (int unsigned idx = 1; idx <= POLICY_CASE_COUNT; idx++)
          run_policy_case_by_index(idx, idx, unmatched_dat_addr,
                                   hci_helper);
        cases_run = POLICY_CASE_COUNT;
      end
      else begin
        run_policy_case_by_index(ACTIVE_POLICY_CASE, 1,
                                 unmatched_dat_addr, hci_helper);
        cases_run = 1;
      end

      vseq_ctx.cfg.vif.i3c_controller_expected_ack = 1'b1;
      if ((vseq_ctx.cfg.ibi_controller_expected_events != cases_run) ||
          (vseq_ctx.cfg.ibi_controller_actual_events != cases_run))
        `uvm_error("IBI_CTRL_POLICY_EVENT_COUNT",
                   $sformatf("Expected/actual events must be %0d/%0d, got %0d/%0d",
                             cases_run, cases_run,
                             vseq_ctx.cfg.ibi_controller_expected_events,
                             vseq_ctx.cfg.ibi_controller_actual_events))
      if ((vseq_ctx.cfg.ibi_cov_attempt_samples < cases_run) ||
          (vseq_ctx.cfg.ibi_cov_completion_samples < cases_run) ||
          (vseq_ctx.cfg.ibi_cov_queue_irq_samples < cases_run))
        `uvm_error("IBI_CTRL_POLICY_COVERAGE",
                   $sformatf("Missing policy coverage samples attempt=%0d completion=%0d queue_irq=%0d",
                             vseq_ctx.cfg.ibi_cov_attempt_samples,
                             vseq_ctx.cfg.ibi_cov_completion_samples,
                             vseq_ctx.cfg.ibi_cov_queue_irq_samples))
      if (vseq_ctx.cfg.ibi_sb_mismatch_count != 0)
        `uvm_error("IBI_CTRL_POLICY_SB",
                   $sformatf("Controller policy scoreboard mismatches=%0d",
                             vseq_ctx.cfg.ibi_sb_mismatch_count))

      `uvm_info("IBI_CTRL_POLICY",
                $sformatf("Completed %0d policy case(s) [%s]",
                          cases_run,
                          RUN_ALL_IN_ONE_SEQ ? "all-in-one-seq" :
                            $sformatf("single case %0d", ACTIVE_POLICY_CASE)),
                UVM_LOW)
    end
`else
    `uvm_fatal("IBI_CTRL_POLICY_RAL_BUILD",
               "Controller policy test requires SMC_USE_I3C_RAL")
`endif
`else
    `uvm_fatal("IBI_CTRL_POLICY_RTL_BUILD",
               "Controller policy test requires SMC_USE_I3C_RTL")
`endif
  endtask
endclass : smc_i3c_ibi_controller_policy_vseq

`endif // SMC_I3C_IBI_CONTROLLER_POLICY_VSEQ_SV
