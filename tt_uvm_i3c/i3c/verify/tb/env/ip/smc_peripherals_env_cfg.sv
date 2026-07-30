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
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-25
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
    bit require_ibi_coverage_samples = 1'b0;
    bit require_ibi_passive_monitor_match = 1'b0;
    int unsigned ibi_timeout_cycles = 200_000;
    int unsigned ibi_retry_count = 0;
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
    bit [1:0] ibi_bus_state = 2'd0;
    int unsigned ibi_cov_attempt_samples;
    int unsigned ibi_cov_completion_samples;
    int unsigned ibi_cov_queue_irq_samples;
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
    bit ibi_controller_dat_index_valid[int unsigned];
    bit [6:0] ibi_controller_dat_addr_by_index[int unsigned];
    int unsigned ibi_controller_target_count = 1;
    bit [6:0] ibi_secondary_target_addr;
    int unsigned ibi_controller_arbitration_losses;
    int unsigned ibi_controller_loser_release_checks;
    int unsigned ibi_controller_loser_release_failures;
    int unsigned ibi_controller_expected_events;
    int unsigned ibi_controller_actual_events;
    int unsigned ibi_controller_irq_events;
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
    virtual i3c_if i3c_secondary_vif;
    i3c_agent_cfg i3c_cfg;
    i3c_agent_cfg i3c_secondary_cfg;
`endif
`ifdef SMC_USE_I3C_RAL
    smc_i3c_ral_model ral_model;
`endif

    function new(string name = "smc_peripherals_env_cfg");
        super.new(name);
    endfunction

    function bit [2:0] resolve_ibi_source_instance(bit [6:0] addr);
        if (ibi_source_instance_by_addr.exists(addr))
            return ibi_source_instance_by_addr[addr];
        return ibi_source_instance;
    endfunction
endclass : smc_peripherals_env_cfg
