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
// File        : smc_peripherals_env_cfg.sv
// Description : Configuration object for the SMC peripheral environment.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-06
//
// *****************************************************************************

typedef enum bit {
    SMC_I3C_IBI_DUT_TARGET     = 1'b0,
    SMC_I3C_IBI_DUT_CONTROLLER = 1'b1
} smc_i3c_ibi_dut_role_e;

class smc_peripherals_env_cfg extends uvm_object;
    `uvm_object_utils(smc_peripherals_env_cfg)

    virtual smc_peripherals_if vif;
    bit has_rtl = 1'b0;

    // Shared AXI4-Lite reg-access bus (P6). Agent built when enabled.
    virtual axi4lite_if #(TB_ADDR_WIDTH, TB_DATA_WIDTH) bus_vif;
    axi4lite_config     #(TB_ADDR_WIDTH, TB_DATA_WIDTH) bus_cfg;
    bit has_local_bus_agent = 1'b1;
    bit has_scoreboard = 1'b1;
    longint unsigned i3c_base_address = 'h0040_0000;
    longint unsigned i3c_window_bytes = 'h1000;
    smc_i3c_csr_scoreboard_cfg #(TB_ADDR_WIDTH, TB_DATA_WIDTH) scoreboard_cfg;
    bit has_ral = 1'b1;
    uvm_reg_cvr_t ral_coverage_models = UVM_NO_COVERAGE;
    smc_i3c_ibi_dut_role_e ibi_dut_role = SMC_I3C_IBI_DUT_TARGET;
    bit [6:0] ibi_target_addr = TB_DEFAULT_IBI_TARGET_ADDR;
    bit [7:0] ibi_basic_mdb = 8'ha5;
    bit ibi_expected_ack = 1'b1;
    ibi_terminal_status_e ibi_expected_terminal_status = IBI_STATUS_SUCCESS;
    bit has_ibi_coverage = 1'b0;
    bit has_ibi_scoreboard = 1'b0;
    bit has_ibi_controller_checker = 1'b0;
    bit has_ibi_recovery_checker = 1'b0;
    // A DUT-Target multi-requester test can place another UVM Target on the
    // same bus.  The Host observes both addresses, but the DUT descriptor
    // scoreboard must consume only transactions sourced by the DUT Target.
    bit ibi_filter_external_target_observations = 1'b0;
    bit require_ibi_coverage_samples = 1'b0;
    bit require_ibi_passive_monitor_match = 1'b0;
    // Queue-threshold IRQs describe FIFO state rather than one edge per IBI
    // record. Single-record Controller tests keep the strict default; the
    // multi-record FIFO test checks the coalesced IRQ at queue level.
    bit require_ibi_controller_record_irq = 1'b1;
    // Asserted only for a real requester presented while the Controller IBI
    // receive FIFO is full. DAT policy still matches, but capacity requires
    // an address NACK and a zero-length status record after space is freed.
    bit ibi_controller_fifo_full_expected_nack = 1'b0;
    int unsigned ibi_timeout_cycles = 200_000;
    int unsigned ibi_retry_count = 0;
    // Keep one Target descriptor correlated across retryable NACK/address-
    // arbitration attempts. Intermediate attempts feed coverage; only the
    // terminal result is published to the descriptor scoreboard.
    bit ibi_retry_tracking = 1'b0;
    // A Target that loses address arbitration has no Host observation for
    // its own address. In the focused DUT-loss correlation case, allow the
    // observer to bind IBI_DONE/LAST_IBI_STATUS to the pending IBI_PORT
    // descriptor and publish an intermediate coverage-only completion.
    bit ibi_address_arb_status_correlation = 1'b0;
    // A finite-retry exhaustion terminates architecturally with
    // LAST_IBI_STATUS=FAILURE_RETRY on the final permitted bus attempt.
    // Enable the observer's terminal correlation for that focused scenario;
    // ordinary retry tests still require a final ACKed bus attempt.
    bit ibi_retry_exhaustion = 1'b0;
    // Focused Target-TX protocol-error mode: the Host terminates an ACKed IBI
    // after a short prefix while the descriptor still advertises more data.
    // The Host VIP includes its termination boundary in the returned byte
    // stream, while the passive monitor publishes only bytes completed before
    // that boundary. Keep the two independently observed prefixes explicit.
    bit ibi_expect_partial_data = 1'b0;
    int unsigned ibi_partial_host_rx_bytes = 2;
    int unsigned ibi_partial_passive_bytes = 1;
    int unsigned ibi_observed_retry_count;
    int unsigned ibi_observed_attempt_count;
    // IBI_QUEUE_SIZE is encoded as 2^(N+1). Keep both the CSR encoding and
    // the decoded FIFO capacity so tests never treat encoding 4 as four words.
    int unsigned ibi_queue_size_code = 4;
    int unsigned ibi_queue_size = 32;
    bit [7:0] ibi_bcr;
    bit ibi_bcr_valid = 1'b0;
    ibi_addr_class_e ibi_addr_class = IBI_ADDR_UNCLASSIFIED;
    bit ibi_addr_class_valid = 1'b0;
    bit [2:0] ibi_source_instance = 3'd0;
    bit [2:0] ibi_source_instance_by_addr[bit [6:0]];
    int unsigned ibi_requester_count = 1;
    bit [1:0] ibi_arb_outcome = 2'd0;
    bit ibi_dut_wins_arbitration = 1'b0;
    bit [1:0] ibi_bus_state = 2'd0;
    int unsigned ibi_cov_attempt_samples;
    int unsigned ibi_cov_completion_samples;
    int unsigned ibi_cov_queue_irq_samples;
    int unsigned ibi_cov_recovery_samples;
    int unsigned ibi_cov_threshold_below_samples;
    int unsigned ibi_cov_threshold_reached_samples;
    int unsigned ibi_sb_completion_count;
    int unsigned ibi_sb_mismatch_count;
    int unsigned ibi_controller_dat_index = 0;
    bit ibi_controller_dat_valid = 1'b0;
    bit [6:0] ibi_controller_dat_dynamic_addr;
    bit ibi_controller_dat_ibi_reject = 1'b0;
    bit ibi_controller_dat_ibi_payload = 1'b1;
    bit ibi_controller_dat_valid_by_addr[bit [6:0]];
    bit ibi_controller_dat_reject_by_addr[bit [6:0]];
    bit ibi_controller_dat_payload_by_addr[bit [6:0]];
    bit [7:0] ibi_controller_dat_autocmd_mask_by_addr[bit [6:0]];
    bit [7:0] ibi_controller_dat_autocmd_value_by_addr[bit [6:0]];
    bit [2:0] ibi_controller_dat_autocmd_mode_by_addr[bit [6:0]];
    // Expected Private Read data for a matched HCI Auto-Command. This is
    // supplied by the UVM Target scenario and lets the Controller predictor
    // model the coalesced IBI record independently of DUT output.
    byte unsigned ibi_controller_autocmd_expected_data[$];
    bit ibi_controller_dat_index_valid[int unsigned];
    bit [6:0] ibi_controller_dat_addr_by_index[int unsigned];
    // Total simultaneous IBI requesters represented by this scenario. The
    // infrastructure supports 1..TB_MAX_IBI_REQUESTERS (currently four).
    int unsigned ibi_controller_target_count = 1;
    bit [6:0] ibi_target_addr_by_slot[TB_MAX_IBI_REQUESTERS];
    bit ibi_target_driver_armed[TB_MAX_IBI_REQUESTERS];
    bit ibi_target_driver_start_seen[TB_MAX_IBI_REQUESTERS];
    bit ibi_target_driver_completed[TB_MAX_IBI_REQUESTERS];
    bit [6:0] ibi_target_driver_resolved_addr[TB_MAX_IBI_REQUESTERS];
    bit ibi_target_driver_ack[TB_MAX_IBI_REQUESTERS];
    bit ibi_target_driver_arbitration_won[TB_MAX_IBI_REQUESTERS];
    bit ibi_target_driver_released[TB_MAX_IBI_REQUESTERS];
    bit ibi_target_driver_barrier_enable;
    bit ibi_target_driver_release;
    bit [6:0] ibi_secondary_target_addr;
    int unsigned ibi_controller_arbitration_losses;
    int unsigned ibi_controller_loser_release_checks;
    int unsigned ibi_controller_loser_release_failures;
    int unsigned ibi_controller_expected_events;
    int unsigned ibi_controller_actual_events;
    int unsigned ibi_controller_flushed_events;
    int unsigned ibi_controller_irq_events;
    // Negative Controller scenarios whose PASS condition is that no IBI ever
    // completes. The Controller scoreboard's default "zero events means nothing
    // was checked" rule inverts for these: zero is the requirement, and any
    // observed event is the failure. In this mode the event-count rules replace
    // the unmatched-queue nets rather than adding to them, so one stray event
    // is reported once.
    bit ibi_expect_zero_events = 1'b0;
    // Controller IBI timing-context selection and per-test evidence counters.
    // Context encoding: 0=idle, 1=after transfer, 2=busy/defer, 3=all.
    int unsigned ibi_timing_context = 3;
    int unsigned ibi_timing_pending_busy_samples;
    int unsigned ibi_timing_no_start_busy_checks;
    int unsigned ibi_timing_normal_xfer_checks;
    int unsigned ibi_timing_retry_after_taval_samples;
    // Count of policy IBI cases the vseq launched (incremented per case at
    // launch, before arm/completion) so the controller scoreboard summary can
    // account for cases that never complete on the bus (RTL A.3 wedge). Left 0
    // by tests that do not use it, which disables the related summary lines
    // and the incomplete-cases check.
    int unsigned ibi_controller_attempt_cases;
`ifdef SMC_USE_I3C_RTL
    bit has_i3c_agent = 1'b0;
    virtual i3c_if i3c_vif;
    virtual i3c_if i3c_target_vif[TB_MAX_IBI_REQUESTERS];
    virtual i3c_if i3c_secondary_vif;
    i3c_agent_cfg i3c_cfg;
    i3c_agent_cfg i3c_target_cfg[TB_MAX_IBI_REQUESTERS];
    i3c_agent_cfg i3c_secondary_cfg;
`endif
`ifdef SMC_USE_I3C_RAL
    smc_i3c_ral_model ral_model;
`endif

    function new(string name = "smc_peripherals_env_cfg");
        super.new(name);
        ibi_target_addr_by_slot[0] = TB_DEFAULT_IBI_TARGET_ADDR;
        ibi_target_addr_by_slot[1] = 7'h52;
        ibi_target_addr_by_slot[2] = 7'h4a;
        ibi_target_addr_by_slot[3] = 7'h42;
    endfunction

    function void sync_ibi_target_slots();
        ibi_target_addr_by_slot[0] = ibi_target_addr;
        if (ibi_secondary_target_addr != '0)
            ibi_target_addr_by_slot[1] = ibi_secondary_target_addr;
        else
            ibi_secondary_target_addr = ibi_target_addr_by_slot[1];
        for (int unsigned slot = 0;
             slot < ibi_controller_target_count; slot++) begin
            for (int unsigned prior = 0; prior < slot; prior++) begin
                if (ibi_target_addr_by_slot[slot] ==
                    ibi_target_addr_by_slot[prior])
                    `uvm_fatal("IBI_TARGET_ADDR_DUPLICATE",
                               $sformatf("IBI Target slots %0d and %0d both use address 0x%02h",
                                         prior, slot,
                                         ibi_target_addr_by_slot[slot]))
            end
            ibi_source_instance_by_addr[ibi_target_addr_by_slot[slot]] =
              slot[2:0];
        end
    endfunction

    function void clear_ibi_target_driver_state();
        foreach (ibi_target_driver_armed[slot]) begin
            ibi_target_driver_armed[slot] = 1'b0;
            ibi_target_driver_start_seen[slot] = 1'b0;
            ibi_target_driver_completed[slot] = 1'b0;
            ibi_target_driver_resolved_addr[slot] = '0;
            ibi_target_driver_ack[slot] = 1'b0;
            ibi_target_driver_arbitration_won[slot] = 1'b0;
            ibi_target_driver_released[slot] = 1'b0;
        end
        ibi_target_driver_release = 1'b0;
    endfunction

    function bit [2:0] resolve_ibi_source_instance(bit [6:0] addr);
        if (ibi_source_instance_by_addr.exists(addr))
            return ibi_source_instance_by_addr[addr];
        return ibi_source_instance;
    endfunction
endclass : smc_peripherals_env_cfg
